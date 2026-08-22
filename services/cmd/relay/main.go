// Command relay runs the Civic Commons Messaging Relay Service (Task 4.4).
//
// Responsibilities (per MASTER_PLAN Task 4.4):
//   - WebSocket connection management (first-frame JWT auth, 25s/10s heartbeat)
//   - Ciphertext envelope routing (authenticated sender hash → recipient hash)
//   - Offline queue on Redis Streams with a 30-day retention window
//   - Multi-device fan-out
//   - Delivery acknowledgements and queue purge
//   - Connection Request state machine (accept events published to NATS)
//
// ZERO-KNOWLEDGE: the relay is a ciphertext router. It never decrypts or
// inspects message bodies; access tokens are verified against the identity
// service's RS256 public key (from Vault, or a dev fallback outside
// production).
package main

import (
	"context"
	"crypto/rsa"
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
	"github.com/kankan223/pari/services/internal/events"
	"github.com/kankan223/pari/services/internal/idempotency"
	"github.com/kankan223/pari/services/internal/identity"
	"github.com/kankan223/pari/services/internal/logging"
	"github.com/kankan223/pari/services/internal/relay"
	"github.com/kankan223/pari/services/internal/vault"
	"github.com/kankan223/pari/services/pkg/version"
)

func main() {
	// The relay runs alongside the identity service (default :8080) — give it
	// a distinct default port so both can be started together in dev without
	// a bind conflict (README documents HTTP_PORT=8081 for the relay).
	if os.Getenv("HTTP_PORT") == "" {
		_ = os.Setenv("HTTP_PORT", "8081")
	}
	if os.Getenv("SERVICE_NAME") == "" {
		_ = os.Setenv("SERVICE_NAME", "relay")
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
		logger.Error("relay service exited", "err", err.Error())
		os.Exit(1)
	}
}

func run(cfg config.Config, logger *slog.Logger) error {
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()

	// --- JWT verification key (Vault-first; dev fallback gated by config) ---
	pubKey, err := resolvePublicKey(ctx, cfg, logger)
	if err != nil {
		return err
	}
	auth := &tokenAuthenticator{
		verifier: identity.NewJWTVerifier(pubKey, cfg.JWTIssuer, cfg.JWTAudience),
	}

	// --- Redis-backed offline queue (Upstash HTTP when URL detected, otherwise Sentinel/standalone) ---
	var redisClient cache.RedisClient
	var redisCloser func() error
	var redisHealthy bool

	if upstashBase, upstashToken, ok := cache.ParseUpstashURL(cfg.RedisAddr); ok {
		redisClient = cache.NewUpstashClient(upstashBase, upstashToken)
		redisCloser = func() error { return nil }
		redisHealthy = true
		logger.Info("redis client", "mode", "upstash-http")
	} else {
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
		redisClient = &cache.RedisClientAdapter{Client: rdb}
		redisCloser = rdb.Close
		probeCtx, cancelProbe := context.WithTimeout(ctx, 5*time.Second)
		probeErr := cache.Ping(probeCtx, rdb)
		cancelProbe()
		if probeErr != nil {
			logger.Error("redis health probe failed at startup", "error", probeErr.Error(), "mode", redisMode(cfg))
			if cfg.Environment == "production" {
				return fmt.Errorf("redis unreachable at startup: %w", probeErr)
			}
		} else {
			redisHealthy = true
			logger.Info("redis connected", "mode", redisMode(cfg))
		}
	}
	defer func() { _ = redisCloser() }()

	var queue relay.OfflineQueue
	var idemStore idempotency.Store
	if !redisHealthy {
		logger.Warn("redis unavailable — using in-memory stores (data lost on restart)")
		queue = relay.NewInMemoryOfflineQueue(cfg.OfflineQueueTTL)
		idemStore = idempotency.NewInMemoryStore()
	} else {
		queue = relay.NewRedisOfflineQueue(redisClient, cfg.OfflineQueueTTL)
		idemStore = idempotency.NewRedisStore(redisClient)
	}
	hub := relay.NewHub(queue)

	// --- Idempotency dedup for mutation endpoints (Task 5.3) ---
	idem := idempotency.NewMiddleware(idemStore, cfg.IdempotencyTTL, logger)

	// --- Event bus (NATS JetStream; noop fallback so dev runs without a
	// broker) ---
	var publisher relay.EventPublisher = relay.NoopEventPublisher{}
	if bus, err := events.NewClient(events.Options{
		URL:            cfg.NATSURL,
		StreamName:     cfg.NATSStreamName,
		Storage:        cfg.NATSStorage,
		MaxAge:         cfg.NATSMaxAge,
		MaxReconnects:  cfg.NATSMaxReconnects,
		ReconnectWait:  cfg.NATSReconnectWait,
		ConnectTimeout: cfg.NATSConnectTimeout,
		Log:            logger,
	}); err != nil {
		logger.Warn("nats unavailable — using noop event publisher", "error", err.Error())
	} else {
		defer func() { _ = bus.Close() }()
		// The stream captures every registered subject; storage and retention
		// follow NATS_STORAGE / NATS_MAX_AGE (defaults file/30d).
		streamCfg := events.DefaultStreamConfig()
		streamCfg.Storage = cfg.NATSStorage
		streamCfg.MaxAge = cfg.NATSMaxAge
		if err := bus.EnsureStream(ctx, streamCfg); err != nil {
			logger.Warn("nats stream init failed — using noop event publisher", "error", err.Error())
		} else {
			publisher = bus
			logger.Info("event bus connected (JetStream)", "url", cfg.NATSURL, "stream", cfg.NATSStreamName)
		}
	}

	// --- Connection requests ---
	// When RequirePostgres is true (production), use PostgreSQL-backed store.
	// When false (staging/dev), use in-memory store.
	var reqStore relay.ConnectionRequestStore
	if cfg.RequirePostgres {
		pgDB, err := database.Open(database.DriverPostgres, cfg.PostgresDSN)
		if err != nil {
			return err
		}
		defer func() { _ = pgDB.Close() }()
		if _, err := database.Migrate(ctx, pgDB); err != nil {
			return fmt.Errorf("postgres migrate: %w", err)
		}
		pg := pgstore.New(pgDB, cfg.PGEncKey)
		logger.Info("postgres store connected", "migrated", true)
		reqStore = pg.Requests()
	} else {
		logger.Warn("postgres disabled — using in-memory request store")
		reqStore = relay.NewMemRequestStore()
	}

	requests := relay.NewConnectionRequestManager(
		reqStore, publisher, cfg.ConnectionRequestExpiry,
	)

	// --- HTTP/WS server ---
	srv := relay.NewServer(relay.ServerOptions{
		Hub:           hub,
		Authenticator: auth,
		Requests:      requests,
		Idempotency:   idem,
		Logger:        logger,
		PingInterval:  cfg.WSPingInterval,
		PongTimeout:   cfg.WSPongTimeout,
		QueueTTL:      cfg.OfflineQueueTTL,
	})
	server := &http.Server{
		Addr:              ":" + cfg.HTTPPort,
		Handler:           corsMiddleware(srv.Handler()),
		ReadHeaderTimeout: 10 * time.Second,
		ReadTimeout:       30 * time.Second,
		WriteTimeout:      30 * time.Second,
		IdleTimeout:       60 * time.Second,
	}

	errCh := make(chan error, 1)
	go func() {
		logger.Info("relay service listening", "addr", server.Addr, "version", version.String(), "env", cfg.Environment)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			errCh <- err
		}
	}()

	// Periodic maintenance: expire stale connection requests.
	maintenanceDone := make(chan struct{})
	go func() {
		ticker := time.NewTicker(time.Hour)
		defer ticker.Stop()
		for {
			select {
			case <-ctx.Done():
				close(maintenanceDone)
				return
			case <-ticker.C:
				if n, err := requests.ExpireStale(ctx); err != nil {
					logger.Error("request sweep failed", "error", err.Error())
				} else if n > 0 {
					logger.Info("expired stale connection requests", "count", n)
				}
			}
		}
	}()

	select {
	case err := <-errCh:
		return fmt.Errorf("http server: %w", err)
	case <-ctx.Done():
		logger.Info("shutting down")
		<-maintenanceDone
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		return server.Shutdown(shutdownCtx)
	}
}

// corsMiddleware adds CORS headers to allow the Flutter web frontend
// hosted on Cloudflare Pages to call the relay service API.
func corsMiddleware(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		origin := r.Header.Get("Origin")
		if origin == "" {
			origin = "*"
		}
		w.Header().Set("Access-Control-Allow-Origin", origin)
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		w.Header().Set("Access-Control-Allow-Credentials", "true")
		w.Header().Set("Access-Control-Max-Age", "86400")

		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}

		next.ServeHTTP(w, r)
	})
}

// resolvePublicKey loads the RS256 public key used to verify access tokens.
// In production it comes from Vault; dev fallbacks are gated by config.
func resolvePublicKey(ctx context.Context, cfg config.Config, logger *slog.Logger) (*rsa.PublicKey, error) {
	useVault := cfg.DevJWTPubKeyPEM == "" && cfg.DevJWTKeyPEM == ""

	if useVault {
		if cfg.VaultToken == "" && (cfg.VaultRoleID == "" || cfg.VaultSecretID == "") {
			return nil, errors.New("VAULT_TOKEN or VAULT_ROLE_ID+VAULT_SECRET_ID required (or set IDENTITY_DEV_JWT_PUB_KEY outside production)")
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
			return nil, fmt.Errorf("vault connect: %w", err)
		}
		secret, err := vc.ReadKV2(ctx, cfg.VaultJWTPubKeyPath)
		if err != nil {
			return nil, fmt.Errorf("fetch jwt public key from vault: %w", err)
		}
		pemBytes := vaultSecretValue(secret, "public_key", "value")
		if pemBytes == "" {
			return nil, fmt.Errorf("vault secret %q has no usable public key", cfg.VaultJWTPubKeyPath)
		}
		key, err := identity.ParseRSAPublicKeyPEM([]byte(pemBytes))
		if err != nil {
			return nil, err
		}
		logger.Info("jwt public key resolved from vault", "path", cfg.VaultJWTPubKeyPath)
		return key, nil
	}

	// Dev fallback: an explicit public key, or derive it from the private key
	// the identity service uses (IDENTITY_DEV_JWT_KEY).
	if cfg.DevJWTPubKeyPEM != "" {
		key, err := identity.ParseRSAPublicKeyPEM([]byte(cfg.DevJWTPubKeyPEM))
		if err != nil {
			return nil, fmt.Errorf("IDENTITY_DEV_JWT_PUB_KEY: %w", err)
		}
		logger.Warn("dev fallback jwt public key in use — DO NOT USE IN PRODUCTION")
		return key, nil
	}
	if cfg.DevJWTKeyPEM != "" {
		priv, err := identity.ParseRSAPrivateKeyPEM([]byte(cfg.DevJWTKeyPEM))
		if err != nil {
			return nil, fmt.Errorf("IDENTITY_DEV_JWT_KEY: %w", err)
		}
		logger.Warn("dev fallback jwt key in use (derived public key) — DO NOT USE IN PRODUCTION")
		return &priv.PublicKey, nil
	}
	return nil, errors.New("no jwt public key source configured")
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

// tokenAuthenticator adapts the identity service's RS256 verifier to the
// relay's Authenticator interface.
type tokenAuthenticator struct {
	verifier *identity.JWTVerifier
}

func (a *tokenAuthenticator) Authenticate(_ context.Context, accessToken string) (string, error) {
	claims, err := a.verifier.VerifyAccessToken(accessToken)
	if err != nil {
		return "", err
	}
	// The JWT subject IS the blind_hash_id (identity service contract).
	return claims.Subject, nil
}
