package pgstore

import (
	"context"
	"database/sql"
	"errors"

	"github.com/kankan223/pari/services/internal/relay"
)

// RequestStore implements relay.ConnectionRequestStore on PostgreSQL
// (connection_requests table). CAS semantics (single-transition enforcement)
// come from the guarded UPDATE: only a pending row can be transitioned, so
// two concurrent responders cannot both win.
type RequestStore struct{ s *Store }

// Create implements relay.ConnectionRequestStore. A duplicate pending pair is
// an idempotent no-op (the relay manager treats Create as idempotent while a
// request is pending) — ON CONFLICT DO NOTHING lets the partial unique index
// one_pending_pair absorb a concurrent duplicate without aborting the
// transaction.
func (p *RequestStore) Create(ctx context.Context, req relay.ConnectionRequest) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		_, err := tx.ExecContext(ctx,
			`INSERT INTO connection_requests
			   (id, initiator_hash, target_hash, status, created_at, updated_at, expires_at)
			 VALUES ($1, $2, $3, $4, $5, $6, $7)
			 ON CONFLICT DO NOTHING`,
			req.ID, req.InitiatorHash, req.TargetHash, string(req.Status),
			req.CreatedAt, req.UpdatedAt, req.ExpiresAt)
		return err
	})
}

// Get implements relay.ConnectionRequestStore.
func (p *RequestStore) Get(ctx context.Context, id string) (relay.ConnectionRequest, error) {
	var req relay.ConnectionRequest
	var status string
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`SELECT id, initiator_hash, target_hash, status, created_at, updated_at, expires_at
			 FROM connection_requests WHERE id = $1`, id).
			Scan(&req.ID, &req.InitiatorHash, &req.TargetHash, &status,
				&req.CreatedAt, &req.UpdatedAt, &req.ExpiresAt)
		return scanNoRows(err, relay.ErrRequestNotFound)
	})
	if err != nil {
		return relay.ConnectionRequest{}, err
	}
	req.Status = relay.ConnectionRequestStatus(status)
	return req, nil
}

// Update implements relay.ConnectionRequestStore (CAS on status). The stored
// request must still be pending — a terminal state or a concurrent transition
// fails the guarded UPDATE and surfaces as ErrRequestState.
func (p *RequestStore) Update(ctx context.Context, req relay.ConnectionRequest) error {
	return p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		res, err := tx.ExecContext(ctx,
			`UPDATE connection_requests
			    SET status = $2, updated_at = $3
			  WHERE id = $1 AND status = 'pending'`,
			req.ID, string(req.Status), req.UpdatedAt)
		if err != nil {
			return err
		}
		n, err := res.RowsAffected()
		if err != nil {
			return err
		}
		if n == 0 {
			// Distinguish "gone" from "already transitioned".
			var exists bool
			if err := tx.QueryRowContext(ctx,
				`SELECT EXISTS (SELECT 1 FROM connection_requests WHERE id = $1)`, req.ID).
				Scan(&exists); err != nil {
				return err
			}
			if !exists {
				return relay.ErrRequestNotFound
			}
			return relay.ErrRequestState
		}
		return nil
	})
}

// FindPending implements relay.ConnectionRequestStore.
func (p *RequestStore) FindPending(ctx context.Context, initiator, target string) (relay.ConnectionRequest, bool, error) {
	var req relay.ConnectionRequest
	var status string
	found := false
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		err := tx.QueryRowContext(ctx,
			`SELECT id, initiator_hash, target_hash, status, created_at, updated_at, expires_at
			 FROM connection_requests
			 WHERE initiator_hash = $1 AND target_hash = $2 AND status = 'pending'
			 LIMIT 1`, initiator, target).
			Scan(&req.ID, &req.InitiatorHash, &req.TargetHash, &status,
				&req.CreatedAt, &req.UpdatedAt, &req.ExpiresAt)
		if err != nil {
			if errors.Is(err, sql.ErrNoRows) {
				return nil
			}
			return err
		}
		found = true
		return nil
	})
	if err != nil {
		return relay.ConnectionRequest{}, false, err
	}
	if found {
		req.Status = relay.ConnectionRequestStatus(status)
	}
	return req, found, nil
}

// ListFor implements relay.ConnectionRequestStore.
func (p *RequestStore) ListFor(ctx context.Context, hash string) ([]relay.ConnectionRequest, error) {
	return p.queryList(ctx,
		`SELECT id, initiator_hash, target_hash, status, created_at, updated_at, expires_at
		 FROM connection_requests WHERE initiator_hash = $1 OR target_hash = $1
		 ORDER BY created_at DESC`, hash)
}

// ListPending implements relay.ConnectionRequestStore.
func (p *RequestStore) ListPending(ctx context.Context) ([]relay.ConnectionRequest, error) {
	return p.queryList(ctx,
		`SELECT id, initiator_hash, target_hash, status, created_at, updated_at, expires_at
		 FROM connection_requests WHERE status = 'pending' ORDER BY created_at DESC`, "")
}

func (p *RequestStore) queryList(ctx context.Context, query, arg string) ([]relay.ConnectionRequest, error) {
	out := []relay.ConnectionRequest{}
	err := p.s.withTx(ctx, func(ctx context.Context, tx *sql.Tx) error {
		var rows *sql.Rows
		var err error
		if arg == "" {
			rows, err = tx.QueryContext(ctx, query)
		} else {
			rows, err = tx.QueryContext(ctx, query, arg)
		}
		if err != nil {
			return err
		}
		defer rows.Close() //nolint:errcheck
		for rows.Next() {
			var req relay.ConnectionRequest
			var status string
			if err := rows.Scan(&req.ID, &req.InitiatorHash, &req.TargetHash, &status,
				&req.CreatedAt, &req.UpdatedAt, &req.ExpiresAt); err != nil {
				return err
			}
			req.Status = relay.ConnectionRequestStatus(status)
			out = append(out, req)
		}
		return rows.Err()
	})
	return out, err
}

var _ relay.ConnectionRequestStore = (*RequestStore)(nil)
