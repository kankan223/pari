// Package database provides database-open helpers for the services layer.
//
// Drivers are registered via blank imports:
//   - "postgres" from github.com/lib/pq
//   - "sqlite3"  from github.com/mutecomm/go-sqlcipher (SQLCipher-encrypted)
//
// SECURITY: both drivers back encrypted/remote stores; connection strings are
// passed by callers (never logged here).
package database

import (
	"database/sql"
	"fmt"

	_ "github.com/lib/pq"
	_ "github.com/mutecomm/go-sqlcipher"
)

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
	return db, nil
}
