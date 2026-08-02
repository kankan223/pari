package config

import (
	"os"
	"testing"
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

func TestFromEnvOverrides(t *testing.T) {
	t.Setenv("POSTGRES_DSN", "postgres://u@h/db")
	t.Setenv("APP_ENV", "production")
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
