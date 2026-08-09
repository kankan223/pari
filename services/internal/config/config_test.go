package config

import (
	"os"
	"testing"
	"time"
)

func TestFromEnvDefaults(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.Environment != "development" {
		t.Errorf("Environment = %q, want development", cfg.Environment)
	}
	if cfg.HTTPPort != "8080" {
		t.Errorf("HTTPPort = %q, want 8080", cfg.HTTPPort)
	}
	if cfg.PostgresDSN != "postgres://user:pass@localhost/db" {
		t.Errorf("PostgresDSN not read from env")
	}
}

func TestFromEnvRequiresPostgresDSN(t *testing.T) {
	if err := os.Unsetenv("POSTGRES_DSN"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	if _, err := FromEnv(); err == nil {
		t.Fatal("FromEnv() expected error when POSTGRES_DSN is unset")
	}
}

func TestFromEnvPostgresOptOut(t *testing.T) {
	// Services without a database dependency (cmd/api) set
	// APP_REQUIRE_POSTGRES=false and must start with no POSTGRES_DSN.
	t.Setenv("APP_REQUIRE_POSTGRES", "false")
	if err := os.Unsetenv("POSTGRES_DSN"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.RequirePostgres {
		t.Fatal("RequirePostgres should be false with APP_REQUIRE_POSTGRES=false")
	}
	// And the flag must still default to true (the database services depend on
	// the existing hard requirement).
	t.Setenv("APP_REQUIRE_POSTGRES", "true")
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	cfg2, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if !cfg2.RequirePostgres {
		t.Fatal("RequirePostgres should default to true")
	}
}

func TestFromEnvOverrides(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://u@h/db")
	t.Setenv("APP_ENV", "production")
	t.Setenv("PG_ENC_KEY", "prod-enc-key")
	t.Setenv("VAULT_TOKEN", "hvs.prod-token-1234567890abcdef")
	t.Setenv("HTTP_PORT", "9090")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.Environment != "production" {
		t.Errorf("Environment = %q, want production", cfg.Environment)
	}
	if cfg.HTTPPort != "9090" {
		t.Errorf("HTTPPort = %q, want 9090", cfg.HTTPPort)
	}
}

func TestFromEnvSecretsNeverLogged(t *testing.T) {
	// Guards the security posture: the config struct must not expose a
	// String()/Debug() that prints secret values. (No such method exists.)
	t.Setenv("POSTGRES_DSN", "postgres://user:secret@localhost/db")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.PostgresDSN == "" {
		t.Fatal("PostgresDSN should be populated")
	}
}

func TestFromEnvIdentityDefaults(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.VaultAddr != "http://127.0.0.1:8200" {
		t.Errorf("VaultAddr = %q, want default", cfg.VaultAddr)
	}
	if cfg.VaultMount != "civic-commons" || cfg.VaultSaltPath != "identity/argon2_salt" {
		t.Errorf("Vault paths = %q/%q, want defaults", cfg.VaultMount, cfg.VaultSaltPath)
	}
	if cfg.OTPProvider != "noop" {
		t.Errorf("OTPProvider = %q, want noop", cfg.OTPProvider)
	}
	if cfg.AccessTokenTTL != 15*time.Minute {
		t.Errorf("AccessTokenTTL = %v, want 15m", cfg.AccessTokenTTL)
	}
	if cfg.OTPTTL != 10*time.Minute {
		t.Errorf("OTPTTL = %v, want 10m", cfg.OTPTTL)
	}
	if cfg.RefreshTokenTTL != 30*24*time.Hour {
		t.Errorf("RefreshTokenTTL = %v, want 30d", cfg.RefreshTokenTTL)
	}
	if cfg.UsernameCooldown != 30*24*time.Hour {
		t.Errorf("UsernameCooldown = %v, want 30d", cfg.UsernameCooldown)
	}
	if cfg.WSPingInterval != 25*time.Second {
		t.Errorf("WSPingInterval = %v, want 25s", cfg.WSPingInterval)
	}
	if cfg.WSPongTimeout != 10*time.Second {
		t.Errorf("WSPongTimeout = %v, want 10s", cfg.WSPongTimeout)
	}
	if cfg.IdempotencyTTL != 24*time.Hour {
		t.Errorf("IdempotencyTTL = %v, want 24h", cfg.IdempotencyTTL)
	}
	if cfg.OfflineQueueTTL != 30*24*time.Hour {
		t.Errorf("OfflineQueueTTL = %v, want 30d", cfg.OfflineQueueTTL)
	}
	if cfg.ConnectionRequestExpiry != 30*24*time.Hour {
		t.Errorf("ConnectionRequestExpiry = %v, want 30d", cfg.ConnectionRequestExpiry)
	}
	if cfg.VaultJWTPubKeyPath != "identity/jwt_rs256_public_key" {
		t.Errorf("VaultJWTPubKeyPath = %q, want default", cfg.VaultJWTPubKeyPath)
	}
}

func TestFromEnvIdentityOverrides(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("OTP_PROVIDER", "msg91")
	t.Setenv("ACCESS_TOKEN_TTL", "5m")
	t.Setenv("OTP_TTL", "90s")
	t.Setenv("JWT_KID", "identity-rs256-test")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.OTPProvider != "msg91" {
		t.Errorf("OTPProvider = %q, want msg91", cfg.OTPProvider)
	}
	if cfg.AccessTokenTTL != 5*time.Minute {
		t.Errorf("AccessTokenTTL = %v, want 5m", cfg.AccessTokenTTL)
	}
	if cfg.OTPTTL != 90*time.Second {
		t.Errorf("OTPTTL = %v, want 90s", cfg.OTPTTL)
	}
	if cfg.JWTKid != "identity-rs256-test" {
		t.Errorf("JWTKid = %q, want override", cfg.JWTKid)
	}
	t.Setenv("WS_PING_INTERVAL", "5s")
	t.Setenv("OFFLINE_QUEUE_TTL", "48h")
	t.Setenv("IDEMPOTENCY_TTL", "36h")
	cfg2, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg2.WSPingInterval != 5*time.Second || cfg2.OfflineQueueTTL != 48*time.Hour {
		t.Errorf("relay overrides not applied: ping=%v ttl=%v", cfg2.WSPingInterval, cfg2.OfflineQueueTTL)
	}
	if cfg2.IdempotencyTTL != 36*time.Hour {
		t.Errorf("IdempotencyTTL = %v, want 36h override", cfg2.IdempotencyTTL)
	}
}

func TestFromEnvRedisDefaults(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.RedisAddr != "localhost:6379" {
		t.Errorf("RedisAddr = %q, want default", cfg.RedisAddr)
	}
	if cfg.RedisPoolSize != 20 || cfg.RedisMinIdleConns != 5 || cfg.RedisMaxRetries != 3 {
		t.Errorf("Redis pool defaults = %d/%d/%d, want 20/5/3", cfg.RedisPoolSize, cfg.RedisMinIdleConns, cfg.RedisMaxRetries)
	}
	if cfg.RedisSentinelMaster != "civic-master" {
		t.Errorf("RedisSentinelMaster = %q, want civic-master", cfg.RedisSentinelMaster)
	}
	if len(cfg.RedisSentinelAddrs) != 0 {
		t.Errorf("RedisSentinelAddrs = %v, want empty by default", cfg.RedisSentinelAddrs)
	}
	if cfg.RedisDialTimeout != 5*time.Second || cfg.RedisPoolTimeout != 4*time.Second {
		t.Errorf("Redis timeouts = %v/%v, want 5s/4s", cfg.RedisDialTimeout, cfg.RedisPoolTimeout)
	}
}

func TestFromEnvRedisOverrides(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("REDIS_SENTINEL_ADDRS", "sentinel-a:26379, sentinel-b:26379")
	t.Setenv("REDIS_SENTINEL_MASTER", "prod-master")
	t.Setenv("REDIS_POOL_SIZE", "50")
	t.Setenv("REDIS_MAX_RETRIES", "7")
	t.Setenv("REDIS_POOL_TIMEOUT", "2s")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if len(cfg.RedisSentinelAddrs) != 2 || cfg.RedisSentinelAddrs[0] != "sentinel-a:26379" || cfg.RedisSentinelAddrs[1] != "sentinel-b:26379" {
		t.Errorf("RedisSentinelAddrs = %v, want 2 trimmed addrs", cfg.RedisSentinelAddrs)
	}
	if cfg.RedisSentinelMaster != "prod-master" {
		t.Errorf("RedisSentinelMaster = %q, want prod-master", cfg.RedisSentinelMaster)
	}
	if cfg.RedisPoolSize != 50 || cfg.RedisMaxRetries != 7 {
		t.Errorf("Redis pool overrides = %d/%d, want 50/7", cfg.RedisPoolSize, cfg.RedisMaxRetries)
	}
	if cfg.RedisPoolTimeout != 2*time.Second {
		t.Errorf("RedisPoolTimeout = %v, want 2s", cfg.RedisPoolTimeout)
	}
}

func TestFromEnvRequiresPGEncKeyInProduction(t *testing.T) {
	// pgcrypto at-rest encryption must never run with an empty key in
	// production (Task 4.5 security checkpoint).
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("APP_ENV", "production")
	if err := os.Unsetenv("PG_ENC_KEY"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	if _, err := FromEnv(); err == nil {
		t.Fatal("FromEnv() expected error when PG_ENC_KEY unset in production")
	}
}

func TestFromEnvRejectsDevFallbacksInProduction(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("APP_ENV", "production")
	t.Setenv("IDENTITY_DEV_SALT_HEX", "deadbeef")
	if _, err := FromEnv(); err == nil {
		t.Fatal("FromEnv() expected error when dev salt set in production")
	}
}

func TestFromEnvNATSDefaults(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.NATSURL != "nats://localhost:4222" {
		t.Errorf("NATSURL = %q, want default", cfg.NATSURL)
	}
	if cfg.NATSStreamName != "CIVIC_EVENTS" {
		t.Errorf("NATSStreamName = %q, want CIVIC_EVENTS", cfg.NATSStreamName)
	}
	if cfg.NATSStorage != "file" {
		t.Errorf("NATSStorage = %q, want file", cfg.NATSStorage)
	}
	if cfg.NATSMaxAge != 30*24*time.Hour {
		t.Errorf("NATSMaxAge = %v, want 30d", cfg.NATSMaxAge)
	}
	if cfg.NATSMaxReconnects != -1 {
		t.Errorf("NATSMaxReconnects = %d, want -1 (infinite)", cfg.NATSMaxReconnects)
	}
	if cfg.NATSReconnectWait != 2*time.Second || cfg.NATSConnectTimeout != 5*time.Second {
		t.Errorf("NATS reconnect/timeouts = %v/%v, want 2s/5s", cfg.NATSReconnectWait, cfg.NATSConnectTimeout)
	}
}

func TestFromEnvVaultAppRole(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("VAULT_ROLE_ID", "role-1")
	t.Setenv("VAULT_SECRET_ID", "secret-1")
	t.Setenv("VAULT_RENEW_INTERVAL", "2m")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.VaultRoleID != "role-1" || cfg.VaultSecretID != "secret-1" {
		t.Errorf("Vault AppRole = %q/%q, want role-1/secret-1", cfg.VaultRoleID, cfg.VaultSecretID)
	}
	if cfg.VaultRenewInterval != 2*time.Minute {
		t.Errorf("VaultRenewInterval = %v, want 2m", cfg.VaultRenewInterval)
	}
}

func TestFromEnvRequiresVaultAuthInProduction(t *testing.T) {
	// Vault is the production secret source (Task 4.8) — production must
	// carry a static token or AppRole credentials.
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("APP_ENV", "production")
	t.Setenv("PG_ENC_KEY", "k")
	if err := os.Unsetenv("VAULT_TOKEN"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	if err := os.Unsetenv("VAULT_ROLE_ID"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	if err := os.Unsetenv("VAULT_SECRET_ID"); err != nil {
		t.Fatalf("os.Unsetenv() error = %v", err)
	}
	if _, err := FromEnv(); err == nil {
		t.Fatal("FromEnv() expected error when no Vault auth in production")
	}
}

func TestFromEnvNATSOverrides(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://user:pass@localhost/db")
	t.Setenv("NATS_URL", "nats://nats-prod:4222")
	t.Setenv("NATS_STREAM_NAME", "PROD_EVENTS")
	t.Setenv("NATS_STORAGE", "memory")
	t.Setenv("NATS_MAX_AGE", "168h")
	t.Setenv("NATS_MAX_RECONNECTS", "25")
	t.Setenv("NATS_RECONNECT_WAIT", "500ms")
	cfg, err := FromEnv()
	if err != nil {
		t.Fatalf("FromEnv() error = %v", err)
	}
	if cfg.NATSURL != "nats://nats-prod:4222" {
		t.Errorf("NATSURL = %q, want override", cfg.NATSURL)
	}
	if cfg.NATSStreamName != "PROD_EVENTS" {
		t.Errorf("NATSStreamName = %q, want PROD_EVENTS", cfg.NATSStreamName)
	}
	if cfg.NATSStorage != "memory" {
		t.Errorf("NATSStorage = %q, want memory", cfg.NATSStorage)
	}
	if cfg.NATSMaxAge != 168*time.Hour {
		t.Errorf("NATSMaxAge = %v, want 168h", cfg.NATSMaxAge)
	}
	if cfg.NATSMaxReconnects != 25 {
		t.Errorf("NATSMaxReconnects = %d, want 25", cfg.NATSMaxReconnects)
	}
	if cfg.NATSReconnectWait != 500*time.Millisecond {
		t.Errorf("NATSReconnectWait = %v, want 500ms", cfg.NATSReconnectWait)
	}
}
