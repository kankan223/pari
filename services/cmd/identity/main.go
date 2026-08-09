// Command identity runs the Civic Commons Identity Service (Task 4.3).
//
// Responsibilities (per MASTER_PLAN Task 4.3):
//   - OTP request/verify (MSG91 SMS provider; noop in dev)
//   - Argon2id phone → blind_hash_id with the salt fetched from HashiCorp Vault
//   - Username claim/release with a 30-day cooldown
//   - Device public-key registration
//   - RS256 access tokens (15 min) + rotating refresh tokens (30 days)
//   - Redis-backed OTP codes (10-min TTL) and refresh-token revocation
//
// SECURITY: raw phone numbers are handled in-memory only, never persisted or
// logged; secrets (Vault token, MSG91 key, JWT private key) are never logged.
package main

import (
	"context"
	"crypto/rsa"
	"encoding/hex"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"

	"github.com/kankan223/pari/services/internal/cache"
	"github.com/kankan223/pari/services/internal/config"
	"github.com/kankan223/pari/services/internal/database"
	"github.com/kankan223/pari/services/internal/database/pgstore"
	"github.com/kankan223/pari/services/internal/identity"
	"github.com/kankan223/pari/services/internal/logging"
	"github.com/kankan223/pari/services/internal/vault"
	"github.com/kankan223/pari/services/pkg/version"
)

func main() {
	if os.Getenv("SERVICE_NAME") == "" {
		_ = os.Setenv("SERVICE_NAME", "identity")
	}

	cfg, err := config.FromEnv()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	logLevel := slog.LevelInfo
	if cfg.Environment == "development" {
		logLevel = slog.LevelDebug
	}
	logger := logging.NewRedactingLogger(os.Stdout, logLevel)

	if err := run(cfg, logger); err != nil {
		logger.Error("identity service exited", "err", err.Error())
		os.Exit(1)
	}
}

func run(cfg config.Config, logger *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// --- Secrets resolution (Vault-first; dev fallbacks gated by config) ---
	saltProvider, jwtKey, err := resolveSecrets(ctx, cfg, logger)
	if err != nil {
		return err
	}

	signer := identity.NewJWTSigner(jwtKey, cfg.JWTKid, cfg.JWTIssuer, cfg.JWTAudience, cfg.AccessTokenTTL)
	verifier := identity.NewJWTVerifier(&jwtKey.PublicKey, cfg.JWTIssuer, cfg.JWTAudience)

	// --- Redis-backed stores (Sentinel HA when REDIS_SENTINEL_ADDRS is set) ---
	rdb := cache.NewClient(cache.Options{
		Addr:               cfg.RedisAddr,
		Password:           cfg.RedisPass,
		DB:                 cfg.RedisDB,
		SentinelAddrs:      cfg.RedisSentinelAddrs,
		SentinelMasterName: cfg.RedisSentinelMaster,
		SentinelPassword:   cfg.RedisSentinelPass,
		PoolSize:           cfg.RedisPoolSize,
		MinIdleConns:       cfg.RedisMinIdleConns,
		MaxRetries:         cfg.RedisMaxRetries,
		MinRetryBackoff:    cfg.RedisMinRetryBackoff,
		MaxRetryBackoff:    cfg.RedisMaxRetryBackoff,
		DialTimeout:        cfg.RedisDialTimeout,
		ReadTimeout:        cfg.RedisReadTimeout,
		WriteTimeout:       cfg.RedisWriteTimeout,
		PoolTimeout:        cfg.RedisPoolTimeout,
	})
	defer func() { _ = rdb.Close() }()
	// Health-check probe: ping with a short deadline. In production a core
	// dependency that is unreachable at startup is a deploy error — fail
	// fast (like the PG migration). In dev the failure is logged and the
	// lazy client recovers when Redis returns.
	probeCtx, cancelProbe := context.WithTimeout(ctx, 5*time.Second)
	probeErr := cache.Ping(probeCtx, rdb)
	cancelProbe()
	if probeErr != nil {
		logger.Error("redis health probe failed at startup", "error", probeErr.Error(), "mode", redisMode(cfg))
		if cfg.Environment == "production" {
			return fmt.Errorf("redis unreachable at startup: %w", probeErr)
		}
	} else {
		logger.Info("redis connected", "mode", redisMode(cfg))
	}

	otpStore := identity.NewRedisOtpStore(rdb)
	refreshStore := identity.NewRedisRefreshStore(rdb)
	refreshManager := identity.NewRefreshManager(refreshStore, cfg.RefreshTokenTTL)

	// --- SMS provider ---
	var provider identity.SMSProvider
	switch cfg.OTPProvider {
	case "msg91":
		if cfg.MSG91APIKey == "" || cfg.MSG91TemplateID == "" {
			return errors.New("OTP_PROVIDER=msg91 requires MSG91_API_KEY and MSG91_TEMPLATE_ID")
		}
		provider = identity.NewMSG91Provider(identity.MSG91Config{
			APIKey:     cfg.MSG91APIKey,
			SenderID:   cfg.MSG91SenderID,
			TemplateID: cfg.MSG91TemplateID,
		}, logger)
		logger.Info("sms provider configured", "provider", "msg91")
	default:
		provider = identity.NewNoopProvider(logger)
		logger.Warn("sms provider configured", "provider", "noop (dev only)")
	}

	// --- PostgreSQL-backed stores (Task 4.5) ---
	// The migration is idempotent and advisory-locked, so both services may
	// run it at startup; it only does work on first boot. POSTGRES_DSN must
	// be the civic_app role at runtime — a superuser would bypass RLS.
	pgDB, err := database.Open(database.DriverPostgres, cfg.PostgresDSN)
	if err != nil {
		return err
	}
	defer func() { _ = pgDB.Close() }()
	if _, err := database.Migrate(ctx, pgDB); err != nil {
		return fmt.Errorf("postgres migrate: %w", err)
	}
	if cfg.PGEncKey == "" {
		logger.Warn("PG_ENC_KEY is empty — device keys are stored pgcrypto-encrypted with an empty key; set PG_ENC_KEY outside development")
	}
	pg := pgstore.New(pgDB, cfg.PGEncKey)
	logger.Info("postgres stores connected", "migrated", true)

	svc := identity.NewService(
		saltProvider,
		otpStore,
		provider,
		identity.RandomCodeGenerator{},
		pg.Users(),
		pg.Usernames(),
		pg.Devices(),
		signer,
		verifier,
		refreshManager,
		identity.ServiceConfig{
			OTPTTL:           cfg.OTPTTL,
			AccessTokenTTL:   cfg.AccessTokenTTL,
			RefreshTokenTTL:  cfg.RefreshTokenTTL,
			UsernameCooldown: cfg.UsernameCooldown,
			JWTIssuer:        cfg.JWTIssuer,
			JWTAudience:      cfg.JWTAudience,
			JWTKid:           cfg.JWTKid,
		},
		logger,
	)

	// --- HTTP server ---
	server := &http.Server{
		Addr:              ":" + cfg.HTTPPort,
		Handler:           identity.NewServer(svc, logger).Handler(),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("identity service listening", "addr", server.Addr, "version", version.String(), "env", cfg.Environment)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	select {
	case err := <-errCh:
		return fmt.Errorf("http server: %w", err)
	case <-ctx.Done():
		logger.Info("shutting down")
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}

// resolveSecrets loads the Argon2id salt and the RS256 private key. In
// production (or when no dev fallbacks are set) both come from HashiCorp
// Vault at startup — the salt is sealed for the lifetime of the process.
func resolveSecrets(ctx context.Context, cfg config.Config, logger *slog.Logger) (identity.SaltProvider, *rsa.PrivateKey, error) {
	useVault := cfg.DevSaltHex == "" && cfg.DevJWTKeyPEM == ""

	if useVault {
		if cfg.VaultToken == "" && (cfg.VaultRoleID == "" || cfg.VaultSecretID == "") {
			return nil, nil, errors.New("VAULT_TOKEN or VAULT_ROLE_ID+VAULT_SECRET_ID required (or set IDENTITY_DEV_* fallbacks outside production)")
		}
		// AppRole auth (role_id+secret_id) with background token renewal in
		// production; static token otherwise. Fails fast on any auth error.
		vc, err := vault.Connect(ctx, vault.Options{
			Addr:          cfg.VaultAddr,
			Mount:         cfg.VaultMount,
			Token:         cfg.VaultToken,
			RoleID:        cfg.VaultRoleID,
			SecretID:      cfg.VaultSecretID,
			RenewInterval: cfg.VaultRenewInterval,
			Log:           logger,
		})
		if err != nil {
			return nil, nil, fmt.Errorf("vault connect: %w", err)
		}

		saltProvider := identity.NewVaultSaltProvider(vc, cfg.VaultSaltPath)
		// Fail fast: warm the sealed salt now.
		if _, err := saltProvider.Salt(ctx); err != nil {
			return nil, nil, err
		}

		keySecret, err := vc.ReadKV2(ctx, cfg.VaultJWTKeyPath)
		if err != nil {
			return nil, nil, fmt.Errorf("fetch jwt key from vault: %w", err)
		}
		pemBytes := vaultSecretValue(keySecret, "private_key", "value")
		if pemBytes == "" {
			return nil, nil, fmt.Errorf("vault secret %q has no usable private key", cfg.VaultJWTKeyPath)
		}
		key, err := identity.ParseRSAPrivateKeyPEM([]byte(pemBytes))
		if err != nil {
			return nil, nil, err
		}
		logger.Info("secrets resolved from vault", "mount", cfg.VaultMount, "salt_path", cfg.VaultSaltPath)
		return saltProvider, key, nil
	}

	// Dev-only fallback (config.FromEnv forbids these in production). BOTH
	// dev variables must be set together — a half-set fallback (e.g. only
	// IDENTITY_DEV_SALT_HEX) would otherwise fall through to a cryptic PEM
	// parse error; fail fast with the exact missing variable instead.
	if cfg.DevSaltHex != "" || cfg.DevJWTKeyPEM != "" {
		if cfg.DevSaltHex == "" {
			return nil, nil, errors.New("IDENTITY_DEV_SALT_HEX is required when using dev fallbacks (set with IDENTITY_DEV_JWT_KEY)")
		}
		if cfg.DevJWTKeyPEM == "" {
			return nil, nil, errors.New("IDENTITY_DEV_JWT_KEY is required when using dev fallbacks (set with IDENTITY_DEV_SALT_HEX)")
		}
		saltBytes, err := hex.DecodeString(cfg.DevSaltHex)
		if err != nil {
			return nil, nil, fmt.Errorf("IDENTITY_DEV_SALT_HEX: %w", err)
		}
		key, err := identity.ParseRSAPrivateKeyPEM([]byte(cfg.DevJWTKeyPEM))
		if err != nil {
			return nil, nil, fmt.Errorf("IDENTITY_DEV_JWT_KEY: %w", err)
		}
		logger.Warn("dev fallback secrets in use (IDENTITY_DEV_*) — DO NOT USE IN PRODUCTION")
		return identity.NewStaticSaltProvider(saltBytes), key, nil
	}
	return nil, nil, errors.New("no salt source configured")
}

// redisMode reports whether the client runs in Sentinel failover mode (used
// only for logging; never reveals credentials).
func redisMode(cfg config.Config) string {
	if len(cfg.RedisSentinelAddrs) > 0 {
		return "sentinel"
	}
	return "standalone"
}

// vaultSecretValue returns the first non-empty secret value, preferring the
// named keys (a KV v2 secret may store its value under any key).
func vaultSecretValue(secret map[string]string, preferred ...string) string {
	for _, k := range preferred {
		if v := strings.TrimSpace(secret[k]); v != "" {
			return v
		}
	}
	for _, v := range secret {
		if strings.TrimSpace(v) != "" {
			return v
		}
	}
	return ""
}
