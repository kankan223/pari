package pgstore

import (
	"context"
	"database/sql"
	"errors"
	"fmt"
	"time"

	"github.com/kankan223/pari/services/internal/identity"
)

// UsernameStore implements identity.UsernameStore on PostgreSQL (usernames
// table). Claim/release semantics are byte-for-byte the in-memory store's:
//   - no row            → claim succeeds
//   - row, same owner   → ErrUsernameTaken
//   - row, released_at NULL → ErrUsernameTaken (currently held)
//   - row, now < released_at + cooldown → ErrUsernameCooldown
//   - row, cooldown elapsed → re-claim succeeds
type UsernameStore struct{ s *Store }

// Claim implements identity.UsernameStore. An existing row is locked
// (FOR UPDATE) so concurrent claims serialize on the database rather than a
// process-local mutex; FOR UPDATE takes no lock on a missing row, so the
// first-claim race falls through to the unique index (the loser surfaces as
// ErrUsernameTaken).
func (p *UsernameStore) Claim(ctx context.Context, username, ownerHash string, now time.Time, cooldown time.Duration) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		var rec identity.UsernameRecord
		var released sql.NullTime
		err := tx.QueryRowContext(ctx,
			`SELECT owner_hash, claimed_at, released_at FROM usernames WHERE username = $1 FOR UPDATE`,
			username).Scan(&rec.OwnerHash, &rec.ClaimedAt, &released)
		if err != nil {
			if !errors.Is(err, sql.ErrNoRows) {
				return err
			}
			// Fresh claim.
			if _, err := tx.ExecContext(ctx,
				`INSERT INTO usernames (username, owner_hash, claimed_at) VALUES ($1, $2, $3)`,
				username, ownerHash, now); err != nil {
				// A concurrent claim won the race: it is now taken.
				if isUniqueViolation(err) {
					return fmt.Errorf("%w: %s", identity.ErrUsernameTaken, username)
				}
				return err
			}
			return nil
		}
		if released.Valid {
			rec.ReleasedAt = released.Time
		}
		if rec.OwnerHash == ownerHash {
			return fmt.Errorf("%w: %s already held by this identity", identity.ErrUsernameTaken, username)
		}
		if rec.ReleasedAt.IsZero() {
			return fmt.Errorf("%w: %s", identity.ErrUsernameTaken, username)
		}
		if now.Before(rec.ReleasedAt.Add(cooldown)) {
			return fmt.Errorf("%w: %s (available after %s)", identity.ErrUsernameCooldown, username,
				rec.ReleasedAt.Add(cooldown).Format(time.RFC3339))
		}
		// Cooldown elapsed: re-claim (clears released_at).
		_, err = tx.ExecContext(ctx,
			`UPDATE usernames SET owner_hash = $1, claimed_at = $2, released_at = NULL WHERE username = $3`,
			ownerHash, now, username)
		return err
	})
}

// Release implements identity.UsernameStore. Releases only the current owner.
func (p *UsernameStore) Release(ctx context.Context, username, ownerHash string, now time.Time) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx,
			`UPDATE usernames SET owner_hash = '', released_at = $1 WHERE username = $2 AND owner_hash = $3`,
			now, username, ownerHash)
		if err != nil {
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n == 0 {
			return fmt.Errorf("%w: %s", identity.ErrUsernameNotOwned, username)
		}
		return nil
	})
}

// Get implements identity.UsernameStore (parity with the in-memory store:
// an unknown username surfaces as ErrUsernameNotOwned).
func (p *UsernameStore) Get(ctx context.Context, username string) (identity.UsernameRecord, error) {
	var rec identity.UsernameRecord
	var released sql.NullTime
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`SELECT owner_hash, claimed_at, released_at FROM usernames WHERE username = $1`,
			username).Scan(&rec.OwnerHash, &rec.ClaimedAt, &released)
		return scanNoRows(err, fmt.Errorf("%w: %s", identity.ErrUsernameNotOwned, username))
	})
	if err != nil {
		return identity.UsernameRecord{}, err
	}
	if released.Valid {
		rec.ReleasedAt = released.Time
	}
	return rec, nil
}

// ListAll implements identity.UsernameStore. Returns a paginated slice of
// actively claimed usernames sorted alphabetically.
func (p *UsernameStore) ListAll(ctx context.Context, limit, offset int) (identity.UserListResult, error) {
	var result identity.UserListResult
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		// Count total.
		err := tx.QueryRowContext(ctx,
			`SELECT COUNT(*) FROM usernames WHERE owner_hash != ''`).Scan(&result.Total)
		if err != nil {
			return err
		}
		// Fetch page.
		query := `SELECT username, owner_hash FROM usernames WHERE owner_hash != '' ORDER BY username ASC`
		args := []any{}
		if limit > 0 {
			query += ` LIMIT $1 OFFSET $2`
			args = append(args, limit, offset)
		}
		rows, err := tx.QueryContext(ctx, query, args...)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var l identity.UsernameLookup
			if err := rows.Scan(&l.Username, &l.BlindHashID); err != nil {
				return err
			}
			result.Users = append(result.Users, l)
		}
		return rows.Err()
	})
	if err != nil {
		return identity.UserListResult{}, err
	}
	return result, nil
}
