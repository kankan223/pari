package pgstore

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/kankan223/pari/services/internal/identity"
)

// UserStore implements identity.UserStore on PostgreSQL (users table).
type UserStore struct{ s *Store }

// Create implements identity.UserStore. A duplicate blind_hash_id (or a
// username that already exists) maps to ErrUserExists.
func (p *UserStore) Create(ctx context.Context, u identity.User) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		createdAt := u.CreatedAt
		if createdAt.IsZero() {
			createdAt = time.Now().UTC()
		}
		_, err := tx.ExecContext(ctx,
			`INSERT INTO users (blind_hash_id, username, created_at) VALUES ($1, $2, $3)`,
			u.BlindHashID, nullStr(u.Username), createdAt)
		if err == nil {
			return nil
		}
		if isUniqueViolation(err) {
			return fmt.Errorf("%w: %s", identity.ErrUserExists, u.BlindHashID)
		}
		return err
	})
}

// Get implements identity.UserStore.
func (p *UserStore) Get(ctx context.Context, blindHashID string) (identity.User, error) {
	var u identity.User
	var username sql.NullString
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`SELECT blind_hash_id, username, created_at FROM users WHERE blind_hash_id = $1`,
			blindHashID).Scan(&u.BlindHashID, &username, &u.CreatedAt)
		return scanNoRows(err, fmt.Errorf("%w: %s", identity.ErrUserNotFound, blindHashID))
	})
	if err != nil {
		return identity.User{}, err
	}
	u.Username = username.String
	return u, nil
}

// SetUsername implements identity.UserStore. A username held by another
// identity maps to ErrUsernameTaken; an unknown user to ErrUserNotFound.
func (p *UserStore) SetUsername(ctx context.Context, blindHashID, username string) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx,
			`UPDATE users SET username = NULLIF($2, ''), updated_at = now() WHERE blind_hash_id = $1`,
			blindHashID, username)
		if err != nil {
			if isUniqueViolation(err) {
				return fmt.Errorf("%w: %s", identity.ErrUsernameTaken, username)
			}
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n == 0 {
			return fmt.Errorf("%w: %s", identity.ErrUserNotFound, blindHashID)
		}
		return nil
	})
}

// List implements identity.UserStore. Returns all users sorted by created_at.
func (p *UserStore) List(ctx context.Context) ([]identity.User, error) {
	var users []identity.User
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		rows, err := tx.QueryContext(ctx,
			`SELECT blind_hash_id, username, created_at FROM users ORDER BY created_at ASC`)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var u identity.User
			var username sql.NullString
			if err := rows.Scan(&u.BlindHashID, &username, &u.CreatedAt); err != nil {
				return err
			}
			u.Username = username.String
			users = append(users, u)
		}
		return rows.Err()
	})
	if err != nil {
		return nil, err
	}
	return users, nil
}
