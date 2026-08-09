package pgstore

import (
	"context"
	"database/sql"
	"fmt"
	"time"

	"github.com/kankan223/pari/services/internal/identity"
)

// maxDevicesPerUser mirrors identity's per-identity device cap.
const maxDevicesPerUser = 10

// DeviceStore implements identity.DeviceStore on PostgreSQL (devices table).
//
// ENCRYPTION AT REST: the Ed25519 public key is stored encrypted with
// pgcrypto (`pgp_sym_encrypt(..., current_setting('civic.enc_key'))`). The
// column value is opaque bytea — a raw dump of the table reveals nothing;
// only a session holding the key (i.e. these stores) can decrypt it.
type DeviceStore struct{ s *Store }

// Register implements identity.DeviceStore. Validates the public key, enforces
// the per-identity cap for NEW devices, and upserts (re-registration with the
// same device_id is idempotent and refreshes last_seen_at).
func (p *DeviceStore) Register(ctx context.Context, blindHashID string, d identity.Device) error {
	if d.DeviceID == "" {
		return fmt.Errorf("device: device_id is required")
	}
	if !identity.ValidPublicKey(d.PublicKey) {
		return identity.ErrDeviceInvalidKey
	}

	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		// Serialize registrations per identity so the count-then-insert cap
		// check is atomic (no TOCTOU between concurrent registrations).
		if _, err := tx.ExecContext(ctx,
			"SELECT pg_advisory_xact_lock(hashtext($1))", blindHashID); err != nil {
			return err
		}
		var exists bool
		if err := tx.QueryRowContext(ctx,
			`SELECT EXISTS (SELECT 1 FROM devices WHERE blind_hash_id = $1 AND device_id = $2)`,
			blindHashID, d.DeviceID).Scan(&exists); err != nil {
			return err
		}
		if !exists {
			var count int
			if err := tx.QueryRowContext(ctx,
				`SELECT count(*) FROM devices WHERE blind_hash_id = $1`, blindHashID).Scan(&count); err != nil {
				return err
			}
			if count >= maxDevicesPerUser {
				return identity.ErrDeviceLimit
			}
		}

		registeredAt := d.RegisteredAt
		if registeredAt.IsZero() {
			registeredAt = time.Now().UTC()
		}
		now := time.Now().UTC()
		_, err := tx.ExecContext(ctx,
			`INSERT INTO devices (blind_hash_id, device_id, public_key_enc, registered_at, last_seen_at)
			 VALUES ($1, $2, pgp_sym_encrypt($3, current_setting('civic.enc_key')), $4, $5)
			 ON CONFLICT (blind_hash_id, device_id) DO UPDATE
			   SET public_key_enc = EXCLUDED.public_key_enc, last_seen_at = EXCLUDED.last_seen_at`,
			blindHashID, d.DeviceID, d.PublicKey, registeredAt, now)
		return err
	})
}

// List implements identity.DeviceStore (newest first by registration).
func (p *DeviceStore) List(ctx context.Context, blindHashID string) ([]identity.Device, error) {
	out := []identity.Device{}
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		rows, err := tx.QueryContext(ctx,
			`SELECT device_id,
			        pgp_sym_decrypt(public_key_enc, current_setting('civic.enc_key'))::text,
			        registered_at, last_seen_at
			 FROM devices WHERE blind_hash_id = $1
			 ORDER BY registered_at DESC, device_id DESC`, blindHashID)
		if err != nil {
			return err
		}
		defer rows.Close() //nolint:errcheck
		for rows.Next() {
			var d identity.Device
			if err := rows.Scan(&d.DeviceID, &d.PublicKey, &d.RegisteredAt, &d.LastSeenAt); err != nil {
				return err
			}
			out = append(out, d)
		}
		return rows.Err()
	})
	return out, err
}

// Revoke implements identity.DeviceStore.
func (p *DeviceStore) Revoke(ctx context.Context, blindHashID, deviceID string) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx,
			`DELETE FROM devices WHERE blind_hash_id = $1 AND device_id = $2`, blindHashID, deviceID)
		if err != nil {
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n == 0 {
			return fmt.Errorf("%w: %s", identity.ErrDeviceNotFound, deviceID)
		}
		return nil
	})
}
