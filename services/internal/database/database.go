// Package database provides database-open helpers and the schema migration
// runner for the services layer (Task 4.5).
//
// Drivers are registered via blank imports:
//   - "postgres" from github.com/lib/pq
//   - "sqlite3"  from github.com/mutecomm/go-sqlcipher (SQLCipher-encrypted)
//
// SECURITY: both drivers back encrypted/remote stores; connection strings are
// passed by callers (never logged here).
package database

import (
	"context"
	"database/sql"
	"embed"
	"fmt"
	"sort"
	"strconv"
	"strings"
	"time"

	_ "github.com/lib/pq"
	_ "github.com/mutecomm/go-sqlcipher"
)

//go:embed migrations/*.sql
var migrationsFS embed.FS

// DriverPostgres is the lib/pq driver name.
const DriverPostgres = "postgres"

// DriverSQLCipher is the go-sqlcipher driver name (encrypted SQLite).
const DriverSQLCipher = "sqlite3"

// Open opens a *sql.DB for [driver] using [dsn] (no connection is made until
// the first query, so this is safe to call at startup).
func Open(driver, dsn string) (*sql.DB, error) {
	db, err := sql.Open(driver, dsn)
	if err != nil {
		return nil, fmt.Errorf("open %q database: %w", driver, err)
	}
	// Conservative pool bounds for a sidecar service; overridden by callers
	// when a larger pool is warranted.
	db.SetMaxOpenConns(10)
	db.SetMaxIdleConns(5)
	db.SetConnMaxLifetime(30 * time.Minute)
	return db, nil
}

// ---------------------------------------------------------------------------
// Schema migrations (embedded SQL, forward + rollback).
// ---------------------------------------------------------------------------

// Migration is one versioned schema change with its forward (Up) and
// rollback (Down) scripts. Files live in migrations/ as NNNN_name.up.sql and
// NNNN_name.down.sql and are embedded into the binary at build time.
type Migration struct {
	Version int
	Name    string
	Up      string
	Down    string
}

// Migrations returns the embedded migrations sorted by version, ascending.
func Migrations() ([]Migration, error) {
	entries, err := migrationsFS.ReadDir("migrations")
	if err != nil {
		return nil, fmt.Errorf("read embedded migrations: %w", err)
	}

	byVersion := make(map[int]*Migration)
	var versions []int
	for _, e := range entries {
		name := e.Name()
		var kind, rest string
		switch {
		case strings.HasSuffix(name, ".up.sql"):
			kind, rest = "up", strings.TrimSuffix(name, ".up.sql")
		case strings.HasSuffix(name, ".down.sql"):
			kind, rest = "down", strings.TrimSuffix(name, ".down.sql")
		default:
			continue
		}
		parts := strings.SplitN(rest, "_", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("migration %q: expected NNNN_name", name)
		}
		v, err := strconv.Atoi(parts[0])
		if err != nil {
			return nil, fmt.Errorf("migration %q: bad version: %w", name, err)
		}
		sqlBytes, err := migrationsFS.ReadFile("migrations/" + name)
		if err != nil {
			return nil, err
		}
		m := byVersion[v]
		if m == nil {
			m = &Migration{Version: v, Name: parts[1]}
			byVersion[v] = m
			versions = append(versions, v)
		}
		switch kind {
		case "up":
			m.Up = string(sqlBytes)
		case "down":
			m.Down = string(sqlBytes)
		}
	}
	sort.Ints(versions)

	out := make([]Migration, 0, len(versions))
	for _, v := range versions {
		m := byVersion[v]
		if m.Up == "" || m.Down == "" {
			return nil, fmt.Errorf("migration %d (%s) is missing an up or down script", v, m.Name)
		}
		out = append(out, *m)
	}
	return out, nil
}

const (
	// schemaMigrationsTable records applied versions.
	schemaMigrationsTable = `CREATE TABLE IF NOT EXISTS schema_migrations (
		version    integer     PRIMARY KEY,
		name       text        NOT NULL,
		applied_at timestamptz NOT NULL
	)`
	// migrateLockKey serializes concurrent Migrate/Rollback calls across
	// service instances (both identity and relay run migrations at startup).
	migrateLockKey = 735_504_435 // arbitrary but stable
)

// Migrate applies every pending migration in order. Each migration runs in
// its own transaction (the migration scripts are transactional), so a failure
// rolls back both the DDL and the version record. Safe to call from multiple
// processes concurrently via a session advisory lock.
func Migrate(ctx context.Context, db *sql.DB) (applied []int, err error) {
	migs, err := Migrations()
	if err != nil {
		return nil, err
	}
	if len(migs) == 0 {
		return nil, nil
	}

	conn, err := db.Conn(ctx)
	if err != nil {
		return nil, fmt.Errorf("migrate: acquire conn: %w", err)
	}
	defer conn.Close() //nolint:errcheck

	if _, err := conn.ExecContext(ctx, "SELECT pg_advisory_lock($1)", migrateLockKey); err != nil {
		return nil, fmt.Errorf("migrate: lock: %w", err)
	}
	defer conn.ExecContext(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", migrateLockKey) //nolint:errcheck

	if _, err := conn.ExecContext(ctx, schemaMigrationsTable); err != nil {
		return nil, fmt.Errorf("migrate: ensure version table: %w", err)
	}

	done, err := appliedVersions(ctx, conn)
	if err != nil {
		return nil, err
	}

	for _, m := range migs {
		if done[m.Version] {
			continue
		}
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return applied, fmt.Errorf("migrate %d: begin: %w", m.Version, err)
		}
		if _, err := tx.ExecContext(ctx, m.Up); err != nil {
			_ = tx.Rollback()
			return applied, fmt.Errorf("migrate %d (%s) up: %w", m.Version, m.Name, err)
		}
		if _, err := tx.ExecContext(ctx,
			`INSERT INTO schema_migrations (version, name, applied_at) VALUES ($1, $2, $3)`,
			m.Version, m.Name, time.Now().UTC()); err != nil {
			_ = tx.Rollback()
			return applied, fmt.Errorf("migrate %d: record: %w", m.Version, err)
		}
		if err := tx.Commit(); err != nil {
			return applied, fmt.Errorf("migrate %d: commit: %w", m.Version, err)
		}
		applied = append(applied, m.Version)
	}
	return applied, nil
}

// Rollback reverts the [steps] most recently applied migrations (steps <= 0
// reverts every applied migration). Each rollback runs the migration's Down
// script in a transaction, then removes its version record.
func Rollback(ctx context.Context, db *sql.DB, steps int) (rolledBack []int, err error) {
	migs, err := Migrations()
	if err != nil {
		return nil, err
	}
	byVersion := make(map[int]Migration, len(migs))
	for _, m := range migs {
		byVersion[m.Version] = m
	}

	conn, err := db.Conn(ctx)
	if err != nil {
		return nil, fmt.Errorf("rollback: acquire conn: %w", err)
	}
	defer conn.Close() //nolint:errcheck

	if _, err := conn.ExecContext(ctx, "SELECT pg_advisory_lock($1)", migrateLockKey); err != nil {
		return nil, fmt.Errorf("rollback: lock: %w", err)
	}
	defer conn.ExecContext(context.WithoutCancel(ctx), "SELECT pg_advisory_unlock($1)", migrateLockKey) //nolint:errcheck

	if _, err := conn.ExecContext(ctx, schemaMigrationsTable); err != nil {
		return nil, fmt.Errorf("rollback: ensure version table: %w", err)
	}

	rows, err := conn.QueryContext(ctx, `SELECT version FROM schema_migrations ORDER BY version DESC`)
	if err != nil {
		return nil, fmt.Errorf("rollback: list applied: %w", err)
	}
	var applied []int
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			_ = rows.Close()
			return nil, err
		}
		applied = append(applied, v)
	}
	_ = rows.Close()
	if err := rows.Err(); err != nil {
		return nil, err
	}
	if steps > 0 && len(applied) > steps {
		applied = applied[:steps]
	}

	for _, v := range applied {
		m, ok := byVersion[v]
		if !ok {
			return rolledBack, fmt.Errorf("rollback: no script for applied version %d", v)
		}
		tx, err := conn.BeginTx(ctx, nil)
		if err != nil {
			return rolledBack, fmt.Errorf("rollback %d: begin: %w", v, err)
		}
		if _, err := tx.ExecContext(ctx, m.Down); err != nil {
			_ = tx.Rollback()
			return rolledBack, fmt.Errorf("rollback %d (%s) down: %w", v, m.Name, err)
		}
		if _, err := tx.ExecContext(ctx, `DELETE FROM schema_migrations WHERE version = $1`, v); err != nil {
			_ = tx.Rollback()
			return rolledBack, fmt.Errorf("rollback %d: unrecord: %w", v, err)
		}
		if err := tx.Commit(); err != nil {
			return rolledBack, fmt.Errorf("rollback %d: commit: %w", v, err)
		}
		rolledBack = append(rolledBack, v)
	}
	return rolledBack, nil
}

// appliedVersions returns the set of already-applied versions.
func appliedVersions(ctx context.Context, conn *sql.Conn) (map[int]bool, error) {
	rows, err := conn.QueryContext(ctx, `SELECT version FROM schema_migrations`)
	if err != nil {
		return nil, fmt.Errorf("migrate: read versions: %w", err)
	}
	defer rows.Close() //nolint:errcheck
	out := make(map[int]bool)
	for rows.Next() {
		var v int
		if err := rows.Scan(&v); err != nil {
			return nil, err
		}
		out[v] = true
	}
	return out, rows.Err()
}
