package pgstore

import (
	"context"
	"database/sql"
	"encoding/base64"
	"fmt"
	"net/url"
	"os"
	"testing"

	"github.com/kankan223/pari/services/internal/database"
)

// Live integration tests against a real PostgreSQL (Task 4.5). They are gated
// on CIVIC_TEST_PG_DSN (a superuser postgres:// DSN) and skip cleanly when it
// is unset, so CI without a database still passes.
//
// TestMain provisions one shared scratch database:
//   - DROP/CREATE a dedicated database (never touches existing data)
//   - runs the real migrations
//   - activates civic_app (created NOLOGIN by the migration) with a test
//     password, and creates an RLS "outsider" role with table grants but no
//     RLS policy

const (
	scratchDB    = "civic_test_app"
	appRole      = "civic_app"
	appPassword  = "civic_test_app_pw" // #nosec G101 -- test-only credential for a throwaway local container
	outsiderRole = "civic_rls_outsider"
	ownerRole    = "civic_owner_forcetest"
	testEncKey   = "civic-test-encryption-key"
)

var (
	// adminDB is a superuser connection to the scratch database.
	adminDB *sql.DB
	// appDSN connects as civic_app to the scratch database.
	appDSN string
	// pg is the store handle used by the integration tests.
	pg *Store
)

func TestMain(m *testing.M) {
	dsn := os.Getenv("CIVIC_TEST_PG_DSN")
	if dsn == "" {
		// No database: skip all live tests. `go test` prints the skip reason
		// per test via the harness below.
		os.Exit(m.Run())
	}

	ctx := context.Background()

	admin, err := database.Open(database.DriverPostgres, dsn)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open admin db: %v\n", err)
		os.Exit(1)
	}
	if _, err := admin.ExecContext(ctx, "DROP DATABASE IF EXISTS "+scratchDB+" WITH (FORCE)"); err != nil {
		fmt.Fprintf(os.Stderr, "drop scratch db: %v\n", err)
		os.Exit(1)
	}
	if _, err := admin.ExecContext(ctx, "CREATE DATABASE "+scratchDB); err != nil {
		fmt.Fprintf(os.Stderr, "create scratch db: %v\n", err)
		os.Exit(1)
	}

	scratchDSN, err := swapDSNDB(dsn, scratchDB)
	if err != nil {
		fmt.Fprintf(os.Stderr, "scratch dsn: %v\n", err)
		os.Exit(1)
	}
	adminDB, err = database.Open(database.DriverPostgres, scratchDSN)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open scratch db: %v\n", err)
		os.Exit(1)
	}
	adminDB.SetMaxOpenConns(20)

	// Real migrations.
	if _, err := database.Migrate(ctx, adminDB); err != nil {
		fmt.Fprintf(os.Stderr, "migrate scratch db: %v\n", err)
		os.Exit(1)
	}

	// Activate the app role and create the RLS outsider.
	if _, err := adminDB.ExecContext(ctx, "ALTER ROLE "+appRole+" LOGIN PASSWORD '"+appPassword+"'"); err != nil {
		fmt.Fprintf(os.Stderr, "activate app role: %v\n", err)
		os.Exit(1)
	}
	// Idempotent role creation (roles are cluster-wide and survive across runs).
	for _, r := range []string{outsiderRole, ownerRole} {
		if _, err := adminDB.ExecContext(ctx, "DROP ROLE IF EXISTS "+r); err != nil {
			fmt.Fprintf(os.Stderr, "drop role %s: %v\n", r, err)
			os.Exit(1)
		}
		if _, err := adminDB.ExecContext(ctx, "CREATE ROLE "+r+" NOLOGIN"); err != nil {
			fmt.Fprintf(os.Stderr, "create role %s: %v\n", r, err)
			os.Exit(1)
		}
	}
	if _, err := adminDB.ExecContext(ctx, "ALTER ROLE "+outsiderRole+" LOGIN"); err != nil {
		fmt.Fprintf(os.Stderr, "outsider login: %v\n", err)
		os.Exit(1)
	}
	// Outsider gets table grants + schema usage so that RLS — not GRANTs — is
	// what blocks it (the FORCE RLS test also covers the owner).
	if _, err := adminDB.ExecContext(ctx, "GRANT USAGE ON SCHEMA public TO "+outsiderRole); err != nil {
		fmt.Fprintf(os.Stderr, "grant usage: %v\n", err)
		os.Exit(1)
	}
	if _, err := adminDB.ExecContext(ctx,
		"GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO "+outsiderRole); err != nil {
		fmt.Fprintf(os.Stderr, "grant tables: %v\n", err)
		os.Exit(1)
	}

	appDSN = swapDSNUser(scratchDSN, appRole, appPassword)
	appDB, err := database.Open(database.DriverPostgres, appDSN)
	if err != nil {
		fmt.Fprintf(os.Stderr, "open app db: %v\n", err)
		os.Exit(1)
	}
	appDB.SetMaxOpenConns(20)
	pg = New(appDB, testEncKey)

	code := m.Run()

	_ = adminDB.Close()
	_ = appDB.Close()
	_, _ = admin.ExecContext(context.Background(), "DROP DATABASE IF EXISTS "+scratchDB+" WITH (FORCE)")
	_ = admin.Close()
	os.Exit(code)
}

// requireLive skips a test when no database is configured.
func requireLive(t *testing.T) {
	t.Helper()
	if pg == nil {
		t.Skip("CIVIC_TEST_PG_DSN not set — skipping live PostgreSQL tests")
	}
}

// swapDSNDB replaces the database name in a postgres:// DSN.
func swapDSNDB(dsn, dbname string) (string, error) {
	u, err := url.Parse(dsn)
	if err != nil {
		return "", err
	}
	u.Path = "/" + dbname
	return u.String(), nil
}

// swapDSNUser replaces the user + password in a postgres:// DSN.
func swapDSNUser(dsn, user, pass string) string {
	u, err := url.Parse(dsn)
	if err != nil {
		return dsn
	}
	u.User = url.UserPassword(user, pass)
	return u.String()
}

// rawBase64URL encodes [b] base64url without padding (the identity public-key
// format accepted by the stores).
func rawBase64URL(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}
