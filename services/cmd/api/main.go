// Command api is the Civic Commons API gateway service entry point.
//
// Task 4.1 scaffold: it loads environment-based configuration and exits
// cleanly. The actual gateway (HTTP server, JWT auth, routing) lands in later
// Phase 4 tasks.
package main

import (
	"log/slog"
	"os"

	"github.com/kankan223/pari/services/internal/config"
	"github.com/kankan223/pari/services/internal/logging"
	"github.com/kankan223/pari/services/pkg/version"
)

func main() {
	// The API gateway scaffold has no database dependency — do not require
	// POSTGRES_DSN (config defaults to requiring it for identity/relay).
	_ = os.Setenv("APP_REQUIRE_POSTGRES", "false")

	cfg, err := config.FromEnv()
	if err != nil {
		// Error path: the redacting logger is the only output sink so config
		// errors are never at risk of echoing secrets (and identity/relay use
		// the same handler).
		logger := logging.NewRedactingLogger(os.Stderr, slog.LevelError)
		logger.Error("config error", "error", err.Error())
		os.Exit(1)
	}

	logger := logging.NewRedactingLogger(os.Stdout, slog.LevelInfo)
	// Intentionally minimal: no network listeners yet. Log only non-secret
	// metadata — never credentials or tokens.
	logger.Info("civic-commons api", "version", version.String(), "env", cfg.Environment)
}
