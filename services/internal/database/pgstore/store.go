// Package pgstore provides PostgreSQL-backed implementations of the identity
// and relay store interfaces (Task 4.5: PostgreSQL Schema & Migrations).
//
// All store operations run inside a transaction with the pgcrypto session key
// installed (`SET LOCAL civic.enc_key`), so the encrypted PII columns
// (devices.public_key_enc) can be written and read only through these stores.
// The raw key never appears in queries or logs — it is bound once at
// construction and passed as a bind parameter.
package pgstore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"

	"github.com/lib/pq"

	"github.com/kankan223/pari/services/internal/identity"
)

// Store is the shared handle for the PostgreSQL-backed stores: the *sql.DB
// plus the pgcrypto symmetric key used to encrypt PII columns at rest.
type Store struct {
	db     *sql.DB
	encKey string
}

// New wraps [db] with the pgcrypto encryption key. [encKey] is the value of
// the `civic.enc_key` session GUC (Vault-supplied in production; PG_ENC_KEY).
func New(db *sql.DB, encKey string) *Store {
	return &Store{db: db, encKey: encKey}
}

// withTx runs [fn] inside a transaction with the pgcrypto session key
// installed. Every store operation goes through here — encrypted columns
// cannot be read or written without the key.
func (s *Store) withTx(ctx context.Context, fn func(ctx context.Context, tx *sql.Tx) error) error {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return fmt.Errorf("pgstore: begin: %w", err)
	}
	defer tx.Rollback() //nolint:errcheck // no-op after Commit

	// set_config(..., true) is the parameter-safe form of SET LOCAL — the SET
	// statement itself rejects bind placeholders in the extended protocol.
	if _, err := tx.ExecContext(ctx, "SELECT set_config('civic.enc_key', $1, true)", s.encKey); err != nil {
		return fmt.Errorf("pgstore: set enc key: %w", err)
	}
	if err := fn(ctx, tx); err != nil {
		return err
	}
	if err := tx.Commit(); err != nil {
		return fmt.Errorf("pgstore: commit: %w", err)
	}
	return nil
}

// Users returns the identity.UserStore implementation.
func (s *Store) Users() *UserStore { return &UserStore{s: s} }

// Usernames returns the identity.UsernameStore implementation.
func (s *Store) Usernames() *UsernameStore { return &UsernameStore{s: s} }

// Devices returns the identity.DeviceStore implementation.
func (s *Store) Devices() *DeviceStore { return &DeviceStore{s: s} }

// Requests returns the relay.ConnectionRequestStore implementation.
func (s *Store) Requests() *RequestStore { return &RequestStore{s: s} }

// nullStr maps an empty string to SQL NULL.
func nullStr(v string) any {
	if v == "" {
		return nil
	}
	return v
}

// isUniqueViolation reports whether [err] is a PostgreSQL unique_violation
// (SQLSTATE 23505).
func isUniqueViolation(err error) bool {
	var pgErr *pq.Error
	return errors.As(err, &pgErr) && pgErr.Code == "23505"
}

// scanNoRows maps sql.ErrNoRows to [notFound]; everything else passes through.
func scanNoRows(err error, notFound error) error {
	if errors.Is(err, sql.ErrNoRows) {
		return notFound
	}
	return err
}

// Compile-time interface assertions: the four stores satisfy the identity and
// relay store contracts.
var (
	_ identity.UserStore     = (*UserStore)(nil)
	_ identity.UsernameStore = (*UsernameStore)(nil)
	_ identity.DeviceStore   = (*DeviceStore)(nil)
)
