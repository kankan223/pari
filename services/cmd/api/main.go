// Command api is the Civic Commons API gateway service entry point.
//
// Task 4.1 scaffold: it loads environment-based configuration and exits
// cleanly. The actual gateway (HTTP server, JWT auth, routing) lands in later
// Phase 4 tasks.
package main

import (
	"fmt"
	"os"

	"github.com/kankan223/pari/services/internal/config"
	"github.com/kankan223/pari/services/pkg/version"
)

func main() {
	cfg, err := config.FromEnv()
	if err != nil {
		fmt.Fprintf(os.Stderr, "config error: %v\n", err)
		os.Exit(1)
	}

	// Intentionally minimal: no network listeners yet. Log only non-secret
	// metadata — never credentials or tokens.
	fmt.Printf("civic-commons api %s (env=%s)\n", version.String(), cfg.Environment)
}
