// Package config loads service configuration from environment variables.
//
// SECURITY: values are read from the environment and never logged. Secrets
// (DB passwords, Redis password, MinIO keys) are carried in the struct only —
// nothing here writes them to stdout/stderr or any sink.
package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/kankan223/pari/services/internal/events"
)

// Config holds non-secret settings plus secret credentials (never logged).
type Config struct {
	// Environment is one of development|staging|production.
	Environment string

	// RequirePostgres mandates a non-empty POSTGRES_DSN. Defaults to true
	// (identity/relay need the database); services without a database
	// dependency set APP_REQUIRE_POSTGRES=false (cmd/api).
	RequirePostgres bool

	// Service settings.
	ServiceName string
	HTTPPort    string

	// Postgres DSN (full connection string; treated as secret).
	PostgresDSN string

	// PGEncKey is the pgcrypto symmetric key for PII columns at rest
	// (devices.public_key_enc). Secret; supplied via Vault in production.
	PGEncKey string

	// SQLCipher local database path (encrypted at rest).
	SQLCipherPath string

	// Redis connection (password field is secret).
	RedisAddr string
	RedisPass string
	RedisDB   int

	// Redis Sentinel HA failover (Task 4.6). When SentinelAddrs is non-empty
	// the client follows the Sentinel-elected master; all values are secrets
	// or non-secret topology settings (never logged).
	RedisSentinelAddrs  []string // host:port, comma-separated in REDIS_SENTINEL_ADDRS
	RedisSentinelMaster string
	RedisSentinelPass   string

	// Redis client tuning (Task 4.6): resilient retries + managed pooling.
	RedisPoolSize        int
	RedisMinIdleConns    int
	RedisMaxRetries      int
	RedisMinRetryBackoff time.Duration
	RedisMaxRetryBackoff time.Duration
	RedisDialTimeout     time.Duration
	RedisReadTimeout     time.Duration
	RedisWriteTimeout    time.Duration
	RedisPoolTimeout     time.Duration

	// NATS JetStream event bus (Task 4.7). URL may carry credentials; the
	// client handles them and they are never logged.
	NATSURL            string
	NATSStreamName     string
	NATSStorage        events.StorageType
	NATSMaxAge         time.Duration
	NATSMaxReconnects  int
	NATSReconnectWait  time.Duration
	NATSConnectTimeout time.Duration

	// MinIO (secretKey is secret).
	MinIOEndpoint  string
	MinIOAccessKey string
	MinIOSecretKey string
	MinIOUseSSL    bool

	// HashiCorp Vault (Task 4.8) — secrets are resolved at runtime and never
	// logged. Auth is either a static VaultToken or AppRole credentials
	// (RoleID+SecretID, preferred in production); all carried in the struct
	// only.
	VaultAddr          string
	VaultToken         string
	VaultRoleID        string
	VaultSecretID      string
	VaultMount         string
	VaultRenewInterval time.Duration // background token renewal cadence
	VaultSaltPath      string
	VaultJWTKeyPath    string
	VaultJWTPubKeyPath string

	// OTP SMS provider ("noop" | "msg91"). MSG91APIKey is secret.
	OTPProvider     string
	MSG91APIKey     string
	MSG91SenderID   string
	MSG91TemplateID string

	// Token lifetimes.
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	OTPTTL           time.Duration
	UsernameCooldown time.Duration

	// Messaging Relay (Task 4.4).
	WSPingInterval          time.Duration // server ping cadence
	WSPongTimeout           time.Duration // max wait for a pong before close
	OfflineQueueTTL         time.Duration // Redis Streams message retention
	ConnectionRequestExpiry time.Duration // pending requests auto-expire

	// Idempotency (Task 5.3): how long a completed mutation's dedup key
	// stays replayable in Redis. 24h default — comfortably longer than the
	// client's backoff ceiling (5 min) plus any offline queue dwell time.
	IdempotencyTTL time.Duration

	// JWT claims.
	JWTIssuer   string
	JWTAudience string
	JWTKid      string

	// Dev-only fallbacks for running the identity/relay binaries without
	// Vault. NEVER honored when Environment == "production".
	DevSaltHex      string
	DevJWTKeyPEM    string
	DevJWTPubKeyPEM string
}

// FromEnv reads configuration from the process environment.
func FromEnv() (Config, error) {
	cfg := Config{
		Environment:             getEnv("APP_ENV", "development"),
		RequirePostgres:         getEnv("APP_REQUIRE_POSTGRES", "true") != "false",
		ServiceName:             getEnv("SERVICE_NAME", "api"),
		HTTPPort:                getEnv("HTTP_PORT", "8080"),
		PostgresDSN:             os.Getenv("POSTGRES_DSN"),
		PGEncKey:                os.Getenv("PG_ENC_KEY"),
		SQLCipherPath:           getEnv("SQLCIPHER_PATH", "vault.db"),
		RedisAddr:               getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPass:               os.Getenv("REDIS_PASSWORD"),
		RedisDB:                 0,
		RedisSentinelAddrs:      getCSV("REDIS_SENTINEL_ADDRS"),
		RedisSentinelMaster:     getEnv("REDIS_SENTINEL_MASTER", "civic-master"),
		RedisSentinelPass:       os.Getenv("REDIS_SENTINEL_PASSWORD"),
		RedisPoolSize:           getInt("REDIS_POOL_SIZE", 20),
		RedisMinIdleConns:       getInt("REDIS_MIN_IDLE_CONNS", 5),
		RedisMaxRetries:         getInt("REDIS_MAX_RETRIES", 3),
		RedisMinRetryBackoff:    getDuration("REDIS_MIN_RETRY_BACKOFF", 8*time.Millisecond),
		RedisMaxRetryBackoff:    getDuration("REDIS_MAX_RETRY_BACKOFF", 512*time.Millisecond),
		RedisDialTimeout:        getDuration("REDIS_DIAL_TIMEOUT", 5*time.Second),
		RedisReadTimeout:        getDuration("REDIS_READ_TIMEOUT", 3*time.Second),
		RedisWriteTimeout:       getDuration("REDIS_WRITE_TIMEOUT", 3*time.Second),
		RedisPoolTimeout:        getDuration("REDIS_POOL_TIMEOUT", 4*time.Second),
		NATSURL:                 getEnv("NATS_URL", "nats://localhost:4222"),
		NATSStreamName:          getEnv("NATS_STREAM_NAME", events.DefaultStreamName),
		NATSStorage:             events.StorageType(getEnv("NATS_STORAGE", "file")),
		NATSMaxAge:              getDuration("NATS_MAX_AGE", 30*24*time.Hour),
		NATSMaxReconnects:       getInt("NATS_MAX_RECONNECTS", -1),
		NATSReconnectWait:       getDuration("NATS_RECONNECT_WAIT", 2*time.Second),
		NATSConnectTimeout:      getDuration("NATS_CONNECT_TIMEOUT", 5*time.Second),
		MinIOEndpoint:           getEnv("MINIO_ENDPOINT", "localhost:9000"),
		MinIOAccessKey:          os.Getenv("MINIO_ACCESS_KEY"),
		MinIOSecretKey:          os.Getenv("MINIO_SECRET_KEY"),
		MinIOUseSSL:             getEnv("MINIO_USE_SSL", "false") == "true",
		VaultAddr:               getEnv("VAULT_ADDR", "http://127.0.0.1:8200"),
		VaultToken:              os.Getenv("VAULT_TOKEN"),
		VaultRoleID:             os.Getenv("VAULT_ROLE_ID"),
		VaultSecretID:           os.Getenv("VAULT_SECRET_ID"),
		VaultMount:              getEnv("VAULT_MOUNT", "civic-commons"),
		VaultRenewInterval:      getDuration("VAULT_RENEW_INTERVAL", 5*time.Minute),
		VaultSaltPath:           getEnv("VAULT_SALT_PATH", "identity/argon2_salt"),
		VaultJWTKeyPath:         getEnv("VAULT_JWT_KEY_PATH", "identity/jwt_rs256_private_key"),
		VaultJWTPubKeyPath:      getEnv("VAULT_JWT_PUB_KEY_PATH", "identity/jwt_rs256_public_key"),
		OTPProvider:             getEnv("OTP_PROVIDER", "noop"),
		MSG91APIKey:             os.Getenv("MSG91_API_KEY"),
		MSG91SenderID:           getEnv("MSG91_SENDER_ID", "CIVCOM"),
		MSG91TemplateID:         os.Getenv("MSG91_TEMPLATE_ID"),
		AccessTokenTTL:          getDuration("ACCESS_TOKEN_TTL", 15*time.Minute),
		RefreshTokenTTL:         getDuration("REFRESH_TOKEN_TTL", 30*24*time.Hour),
		OTPTTL:                  getDuration("OTP_TTL", 10*time.Minute),
		UsernameCooldown:        getDuration("USERNAME_COOLDOWN", 30*24*time.Hour),
		WSPingInterval:          getDuration("WS_PING_INTERVAL", 25*time.Second),
		WSPongTimeout:           getDuration("WS_PONG_TIMEOUT", 10*time.Second),
		OfflineQueueTTL:         getDuration("OFFLINE_QUEUE_TTL", 30*24*time.Hour),
		ConnectionRequestExpiry: getDuration("CONNECTION_REQUEST_EXPIRY", 30*24*time.Hour),
		IdempotencyTTL:          getDuration("IDEMPOTENCY_TTL", 24*time.Hour),
		JWTIssuer:               getEnv("JWT_ISSUER", "civic-commons-identity"),
		JWTAudience:             getEnv("JWT_AUDIENCE", "civic-commons"),
		JWTKid:                  getEnv("JWT_KID", "identity-rs256"),
		DevSaltHex:              os.Getenv("IDENTITY_DEV_SALT_HEX"),
		DevJWTKeyPEM:            os.Getenv("IDENTITY_DEV_JWT_KEY"),
		DevJWTPubKeyPEM:         os.Getenv("IDENTITY_DEV_JWT_PUB_KEY"),
	}

	if cfg.Environment == "production" && (cfg.DevSaltHex != "" || cfg.DevJWTKeyPEM != "" || cfg.DevJWTPubKeyPEM != "") {
		return Config{}, fmt.Errorf("dev-only identity fallbacks set in production")
	}

	// Vault is the production secret source (Task 4.8): every production
	// service must present either a static token or AppRole credentials.
	if cfg.Environment == "production" && cfg.VaultToken == "" && (cfg.VaultRoleID == "" || cfg.VaultSecretID == "") {
		return Config{}, fmt.Errorf("VAULT_TOKEN or VAULT_ROLE_ID+VAULT_SECRET_ID is required in production")
	}

	// POSTGRES_DSN is required for every service that actually talks to
	// PostgreSQL (identity, relay — Task 4.5). Services with no database
	// dependency (the API gateway scaffold, cmd/api) opt out by setting
	// APP_REQUIRE_POSTGRES=false; otherwise the config fails fast with a
	// clear message instead of crashing later inside a sql.Open().
	if cfg.RequirePostgres && cfg.PostgresDSN == "" {
		return Config{}, fmt.Errorf("POSTGRES_DSN is required")
	}

	// pgcrypto at-rest encryption (Task 4.5) must never run with an empty key
	// in production — that would encrypt PII columns with a trivially
	// guessable key.
	if cfg.Environment == "production" && cfg.PGEncKey == "" {
		return Config{}, fmt.Errorf("PG_ENC_KEY is required in production (pgcrypto at-rest key)")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}

// getCSV parses a comma-separated env list (empty when unset).
func getCSV(key string) []string {
	raw := os.Getenv(key)
	if raw == "" {
		return nil
	}
	parts := strings.Split(raw, ",")
	out := make([]string, 0, len(parts))
	for _, p := range parts {
		if s := strings.TrimSpace(p); s != "" {
			out = append(out, s)
		}
	}
	return out
}

// getInt parses an env int with a fallback on unset or malformed values.
func getInt(key string, fallback int) int {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	n, err := strconv.Atoi(v)
	if err != nil {
		return fallback
	}
	return n
}

// getDuration parses an env duration (e.g. "10m", "1h") with a fallback on
// unset or malformed values.
func getDuration(key string, fallback time.Duration) time.Duration {
	v := os.Getenv(key)
	if v == "" {
		return fallback
	}
	d, err := time.ParseDuration(v)
	if err != nil {
		return fallback
	}
	return d
}
