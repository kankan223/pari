// Package config loads service configuration from environment variables.
//
// SECURITY: values are read from the environment and never logged. Secrets
// (DB passwords, Redis password, MinIO keys) are carried in the struct only —
// nothing here writes them to stdout/stderr or any sink.
package config

import (
	"fmt"
	"os"
)

// Config holds non-secret settings plus secret credentials (never logged).
type Config struct {
	// Environment is one of development|staging|production.
	Environment string

	// Service settings.
	ServiceName string
	HTTPPort    string

	// Postgres DSN (full connection string; treated as secret).
	PostgresDSN string

	// SQLCipher local database path (encrypted at rest).
	SQLCipherPath string

	// Redis connection (password field is secret).
	RedisAddr string
	RedisPass string
	RedisDB   int

	// NATS URL (embedded credentials are handled by the client, not logged).
	NATSURL string

	// MinIO (secretKey is secret).
	MinIOEndpoint  string
	MinIOAccessKey string
	MinIOSecretKey string
	MinIOUseSSL    bool
}

// FromEnv reads configuration from the process environment.
func FromEnv() (Config, error) {
	cfg := Config{
		Environment:    getEnv("APP_ENV", "development"),
		ServiceName:    getEnv("SERVICE_NAME", "api"),
		HTTPPort:       getEnv("HTTP_PORT", "8080"),
		PostgresDSN:    os.Getenv("POSTGRES_DSN"),
		SQLCipherPath:  getEnv("SQLCIPHER_PATH", "vault.db"),
		RedisAddr:      getEnv("REDIS_ADDR", "localhost:6379"),
		RedisPass:      os.Getenv("REDIS_PASSWORD"),
		RedisDB:        0,
		NATSURL:        getEnv("NATS_URL", "nats://localhost:4222"),
		MinIOEndpoint:  getEnv("MINIO_ENDPOINT", "localhost:9000"),
		MinIOAccessKey: os.Getenv("MINIO_ACCESS_KEY"),
		MinIOSecretKey: os.Getenv("MINIO_SECRET_KEY"),
		MinIOUseSSL:    getEnv("MINIO_USE_SSL", "false") == "true",
	}

	if cfg.PostgresDSN == "" {
		return Config{}, fmt.Errorf("POSTGRES_DSN is required")
	}

	return cfg, nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
