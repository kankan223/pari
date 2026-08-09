package database

import (
	"context"
	"crypto/rand"
	"database/sql"
	"encoding/hex"
	"net/url"
	"os"
	"strings"
	"testing"
)

// --- static checks (run everywhere, no database required) ------------------

func TestMigrationsEmbedded(t *testing.T) {
	migs, err := Migrations()
	if err != nil {
		t.Fatalf("Migrations() error = %v", err)
	}
	if len(migs) == 0 {
		t.Fatal("no migrations embedded")
	}
	for _, m := range migs {
		if m.Version <= 0 {
			t.Errorf("migration version must be positive: %+v", m)
		}
		if m.Name == "" {
			t.Errorf("migration %d has no name", m.Version)
		}
		if strings.TrimSpace(m.Up) == "" {
			t.Errorf("migration %d has empty up script", m.Version)
		}
		if strings.TrimSpace(m.Down) == "" {
			t.Errorf("migration %d has empty down script", m.Version)
		}
	}
	// Versions ascending.
	for i := 1; i < len(migs); i++ {
		if migs[i].Version <= migs[i-1].Version {
			t.Errorf("migrations not sorted: %d after %d", migs[i].Version, migs[i-1].Version)
		}
	}
	t.Logf("embedded migrations: %d", len(migs))
}

func TestMigrationUpDeclaresExtensions(t *testing.T) {
	migs, _ := Migrations()
	up := migs[len(migs)-1].Up
	for _, ext := range []string{"postgis", "pgcrypto", "pg_stat_statements", `"uuid-ossp"`} {
		if !strings.Contains(up, "CREATE EXTENSION IF NOT EXISTS "+ext) {
			t.Errorf("up migration missing extension %s", ext)
		}
	}
}

func TestMigrationUpDeclaresTables(t *testing.T) {
	migs, _ := Migrations()
	up := migs[len(migs)-1].Up
	for _, table := range []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"} {
		if !strings.Contains(up, "CREATE TABLE "+table) {
			t.Errorf("up migration missing table %s", table)
		}
	}
}

func TestMigrationUpEnablesRLSOnEveryTable(t *testing.T) {
	migs, _ := Migrations()
	up := migs[len(migs)-1].Up
	// Every sensitive table must have RLS enabled AND forced, plus a policy.
	enable := strings.Count(up, "ENABLE ROW LEVEL SECURITY;")
	force := strings.Count(up, "FORCE ROW LEVEL SECURITY;")
	policies := strings.Count(up, "CREATE POLICY app_full_access")
	if enable != 5 {
		t.Errorf("expected 5 ENABLE ROW LEVEL SECURITY, got %d", enable)
	}
	if force != 5 {
		t.Errorf("expected 5 FORCE ROW LEVEL SECURITY, got %d", force)
	}
	if policies != 5 {
		t.Errorf("expected 5 CREATE POLICY, got %d", policies)
	}
}

func TestMigrationUpUsesPgcryptoAtRest(t *testing.T) {
	migs, _ := Migrations()
	up := migs[len(migs)-1].Up
	if !strings.Contains(up, "public_key_enc  bytea") {
		t.Error("devices.public_key_enc must be bytea (pgp_sym_encrypt output)")
	}
	if !strings.Contains(up, "pgcrypto") || !strings.Contains(up, "pgp_sym_encrypt") {
		t.Error("up migration must reference pgcrypto / pgp_sym_encrypt for PII columns")
	}
	if !strings.Contains(up, "COMMENT ON COLUMN devices.public_key_enc") {
		t.Error("expected a COMMENT documenting the pgcrypto-encrypted PII column")
	}
}

func TestMigrationDownDropsTables(t *testing.T) {
	migs, _ := Migrations()
	down := migs[len(migs)-1].Down
	for _, table := range []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"} {
		if !strings.Contains(down, "DROP TABLE IF EXISTS "+table) {
			t.Errorf("down migration missing DROP TABLE for %s", table)
		}
	}
}

// --- live integration tests (require CIVIC_TEST_PG_DSN) ---------------------

// testPGBaseDSN returns the CIVIC_TEST_PG_DSN value, skipping the test when
// unset so CI without a database still passes.
func testPGBaseDSN(t *testing.T) string {
	t.Helper()
	dsn := os.Getenv("CIVIC_TEST_PG_DSN")
	if dsn == "" {
		t.Skip("CIVIC_TEST_PG_DSN not set — skipping live PostgreSQL tests")
	}
	return dsn
}

func openDB(t *testing.T, dsn string) *sql.DB {
	t.Helper()
	db, err := Open(DriverPostgres, dsn)
	if err != nil {
		t.Fatalf("Open: %v", err)
	}
	t.Cleanup(func() { _ = db.Close() })
	return db
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

func randomSuffix() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		panic(err)
	}
	return hex.EncodeToString(b)
}

// TestMigrateAndRollbackLive proves the forward and rollback paths against a
// real PostgreSQL: extensions created, tables + RLS present, idempotent
// re-run, and a clean rollback that reverses everything.
func TestMigrateAndRollbackLive(t *testing.T) {
	base := testPGBaseDSN(t)
	ctx := context.Background()

	admin := openDB(t, base)
	dbName := "civic_test_migrate_" + randomSuffix()
	if _, err := admin.ExecContext(ctx, "CREATE DATABASE "+dbName); err != nil {
		t.Fatalf("create scratch db: %v", err)
	}
	defer func() {
		_, _ = admin.ExecContext(context.Background(), "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)")
	}()

	dsn, err := swapDSNDB(base, dbName)
	if err != nil {
		t.Fatalf("swap dsn: %v", err)
	}
	db := openDB(t, dsn)

	// Forward.
	applied, err := Migrate(ctx, db)
	if err != nil {
		t.Fatalf("Migrate() error = %v", err)
	}
	if len(applied) != 1 || applied[0] != 1 {
		t.Fatalf("expected migration 1 applied, got %v", applied)
	}

	// Tables exist.
	for _, table := range []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"} {
		var reg sql.NullString
		if err := db.QueryRowContext(ctx,
			"SELECT to_regclass('public."+table+"')").Scan(&reg); err != nil {
			t.Fatalf("to_regclass(%s): %v", table, err)
		}
		if !reg.Valid {
			t.Errorf("table %s missing after migration", table)
		}
	}

	// Extensions exist.
	exts := map[string]bool{}
	rows, err := db.QueryContext(ctx, `SELECT extname FROM pg_extension`)
	if err != nil {
		t.Fatal(err)
	}
	defer rows.Close() //nolint:errcheck
	for rows.Next() {
		var e string
		if err := rows.Scan(&e); err != nil {
			t.Fatal(err)
		}
		exts[e] = true
	}
	for _, e := range []string{"postgis", "pgcrypto", "pg_stat_statements", "uuid-ossp"} {
		if !exts[e] {
			t.Errorf("extension %s not installed", e)
		}
	}

	// RLS enabled + forced on every table.
	for _, table := range []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"} {
		var rls, force bool
		if err := db.QueryRowContext(ctx,
			`SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = $1`,
			table).Scan(&rls, &force); err != nil {
			t.Fatalf("pg_class(%s): %v", table, err)
		}
		if !rls || !force {
			t.Errorf("table %s: rls=%v force=%v, want both true", table, rls, force)
		}
	}

	// Version recorded; idempotent re-run.
	var count int
	if err := db.QueryRowContext(ctx,
		`SELECT count(*) FROM schema_migrations`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("schema_migrations count = %d, want 1", count)
	}
	again, err := Migrate(ctx, db)
	if err != nil {
		t.Fatalf("second Migrate() error = %v", err)
	}
	if len(again) != 0 {
		t.Errorf("second Migrate() applied %v, want none (idempotent)", again)
	}

	// Rollback.
	rolled, err := Rollback(ctx, db, 0)
	if err != nil {
		t.Fatalf("Rollback() error = %v", err)
	}
	if len(rolled) != 1 || rolled[0] != 1 {
		t.Fatalf("expected migration 1 rolled back, got %v", rolled)
	}
	for _, table := range []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"} {
		var reg sql.NullString
		if err := db.QueryRowContext(ctx,
			"SELECT to_regclass('public."+table+"')").Scan(&reg); err != nil {
			t.Fatalf("to_regclass(%s) after rollback: %v", table, err)
		}
		if reg.Valid {
			t.Errorf("table %s still exists after rollback", table)
		}
	}
}

// TestMigrateConcurrentLive proves two simultaneous Migrate calls are safe
// (advisory lock serializes them; exactly one applies, neither errors).
func TestMigrateConcurrentLive(t *testing.T) {
	base := testPGBaseDSN(t)
	ctx := context.Background()

	admin := openDB(t, base)
	dbName := "civic_test_migrate_race_" + randomSuffix()
	if _, err := admin.ExecContext(ctx, "CREATE DATABASE "+dbName); err != nil {
		t.Fatalf("create scratch db: %v", err)
	}
	defer func() {
		_, _ = admin.ExecContext(context.Background(), "DROP DATABASE IF EXISTS "+dbName+" WITH (FORCE)")
	}()

	dsn, err := swapDSNDB(base, dbName)
	if err != nil {
		t.Fatalf("swap dsn: %v", err)
	}
	db := openDB(t, dsn)

	errCh := make(chan error, 2)
	for i := 0; i < 2; i++ {
		go func() {
			_, err := Migrate(ctx, db)
			errCh <- err
		}()
	}
	for i := 0; i < 2; i++ {
		if err := <-errCh; err != nil {
			t.Fatalf("concurrent Migrate: %v", err)
		}
	}
	var count int
	if err := db.QueryRowContext(ctx, `SELECT count(*) FROM schema_migrations`).Scan(&count); err != nil {
		t.Fatal(err)
	}
	if count != 1 {
		t.Errorf("schema_migrations count = %d after concurrent migrate, want 1", count)
	}
}
