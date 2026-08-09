package relay

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"
)

// Connection request lifecycle (Task 4.4).
//
// A request is created by an initiator targeting another user and flows
// through a strict state machine:
//
//	pending ──(target accepts)──▶ accepted
//	pending ──(target rejects)──▶ rejected
//	pending ──(initiator withdraws)──▶ withdrawn
//	pending ──(expiry / sweeper)──▶ expired
//
// Only a single transition per request is ever legal; the manager enforces it
// with compare-and-swap updates so two concurrent responders cannot both
// succeed. An accepted request fires an EventPublisher notification so the
// relay can fan a "connection established" event to both users' devices.
//
// ZERO-KNOWLEDGE: requests reference only blind_hash_ids — no phone numbers
// or plaintext identifiers ever enter this state machine.

// ConnectionRequestStatus is the request lifecycle state.
type ConnectionRequestStatus string

// Connection request states.
const (
	RequestPending   ConnectionRequestStatus = "pending"
	RequestAccepted  ConnectionRequestStatus = "accepted"
	RequestRejected  ConnectionRequestStatus = "rejected"
	RequestWithdrawn ConnectionRequestStatus = "withdrawn"
	RequestExpired   ConnectionRequestStatus = "expired"
)

// terminal reports whether [s] is a final (non-pending) state.
func (s ConnectionRequestStatus) terminal() bool {
	return s != RequestPending
}

// ConnectionRequest is one connect request between two users.
type ConnectionRequest struct {
	ID            string
	InitiatorHash string
	TargetHash    string
	Status        ConnectionRequestStatus
	CreatedAt     time.Time
	UpdatedAt     time.Time
	ExpiresAt     time.Time
}

// Connection request sentinel errors.
var (
	ErrRequestNotFound  = errors.New("relay: connection request not found")
	ErrRequestState     = errors.New("relay: connection request state transition not allowed")
	ErrRequestForbidden = errors.New("relay: not authorized for this connection request")
)

// ConnectionRequestStore persists requests (CAS on status). In-memory until
// the PostgreSQL schema lands in Task 4.5.
type ConnectionRequestStore interface {
	Create(ctx context.Context, req ConnectionRequest) error
	// Get returns the request; Update applies a CAS status transition and
	// returns ErrRequestState if the stored status differs from [req.Status].
	Get(ctx context.Context, id string) (ConnectionRequest, error)
	Update(ctx context.Context, req ConnectionRequest) error
	// FindPending returns an existing pending request between the pair.
	FindPending(ctx context.Context, initiator, target string) (ConnectionRequest, bool, error)
	// ListFor returns requests where [hash] is initiator or target.
	ListFor(ctx context.Context, hash string) ([]ConnectionRequest, error)
	// ListPending returns every request in the pending state (sweeper).
	ListPending(ctx context.Context) ([]ConnectionRequest, error)
}

// EventPublisher broadcasts domain events (NATS in production, noop in
// tests). Accepted connection requests are published so both users' devices
// can be notified in real time.
type EventPublisher interface {
	Publish(ctx context.Context, subject string, payload []byte) error
}

// ConnectionRequestSubject is the event subject for accepted requests.
const ConnectionRequestSubject = "relay.connection.accepted"

// NoopEventPublisher drops events (dev runs without a broker, and tests).
type NoopEventPublisher struct{}

// Publish implements EventPublisher (no-op).
func (NoopEventPublisher) Publish(context.Context, string, []byte) error { return nil }

// ConnectionRequestManager implements the state machine.
type ConnectionRequestManager struct {
	store  ConnectionRequestStore
	events EventPublisher
	expiry time.Duration
	now    func() time.Time
	log    *slog.Logger
}

// NewConnectionRequestManager builds a manager. [expiry] bounds how long a
// pending request may live before the sweeper (or a lazy read) expires it.
func NewConnectionRequestManager(store ConnectionRequestStore, events EventPublisher, expiry time.Duration) *ConnectionRequestManager {
	return &ConnectionRequestManager{store: store, events: events, expiry: expiry, now: time.Now, log: slog.Default()}
}

// SetClock overrides the time source (tests).
func (m *ConnectionRequestManager) SetClock(now func() time.Time) { m.now = now }

// Create opens a pending request from [initiator] to [target]. An already
// pending request between the same pair is returned unchanged (idempotent,
// prevents request spam).
func (m *ConnectionRequestManager) Create(ctx context.Context, initiator, target string) (*ConnectionRequest, error) {
	if initiator == "" || target == "" {
		return nil, errors.New("relay: empty request party")
	}
	if initiator == target {
		return nil, errors.New("relay: cannot request a connection with yourself")
	}
	if existing, ok, err := m.store.FindPending(ctx, initiator, target); err != nil {
		return nil, err
	} else if ok {
		return &existing, nil
	}

	now := m.now().UTC()
	req := ConnectionRequest{
		ID:            randomHex(16),
		InitiatorHash: initiator,
		TargetHash:    target,
		Status:        RequestPending,
		CreatedAt:     now,
		UpdatedAt:     now,
		ExpiresAt:     now.Add(m.expiry),
	}
	if err := m.store.Create(ctx, req); err != nil {
		return nil, fmt.Errorf("relay: create request: %w", err)
	}
	return &req, nil
}

// Get returns a request, lazily expiring it if overdue.
func (m *ConnectionRequestManager) Get(ctx context.Context, id string) (*ConnectionRequest, error) {
	req, err := m.store.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if req.Status == RequestPending && m.now().UTC().After(req.ExpiresAt) {
		return m.transition(ctx, req, RequestExpired)
	}
	return &req, nil
}

// Accept transitions a pending request to accepted (target-only) and fires
// the connection-established event.
func (m *ConnectionRequestManager) Accept(ctx context.Context, id, actingHash string) (*ConnectionRequest, error) {
	return m.respond(ctx, id, actingHash, RequestAccepted)
}

// Reject transitions a pending request to rejected (target-only).
func (m *ConnectionRequestManager) Reject(ctx context.Context, id, actingHash string) (*ConnectionRequest, error) {
	return m.respond(ctx, id, actingHash, RequestRejected)
}

func (m *ConnectionRequestManager) respond(ctx context.Context, id, actingHash string, to ConnectionRequestStatus) (*ConnectionRequest, error) {
	stored, err := m.store.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if stored.TargetHash != actingHash {
		return nil, ErrRequestForbidden
	}
	req, err := m.transition(ctx, stored, to)
	if err != nil {
		return nil, err
	}
	if to == RequestAccepted && m.events != nil {
		// The transition is already committed — an event-bus failure must
		// not turn a successful accept into a client-visible error (a retry
		// would then 409). Publish is best-effort: log and continue.
		payload, merr := json.Marshal(req)
		if merr != nil {
			m.log.Error("encode accept event", "error", merr.Error())
		} else if perr := m.events.Publish(ctx, ConnectionRequestSubject, payload); perr != nil {
			m.log.Error("publish accept event", "request_id", req.ID, "error", perr.Error())
		}
	}
	return req, nil
}

// Withdraw cancels a pending request (initiator-only).
func (m *ConnectionRequestManager) Withdraw(ctx context.Context, id, actingHash string) (*ConnectionRequest, error) {
	req, err := m.store.Get(ctx, id)
	if err != nil {
		return nil, err
	}
	if req.InitiatorHash != actingHash {
		return nil, ErrRequestForbidden
	}
	return m.transition(ctx, req, RequestWithdrawn)
}

// ExpireStale sweeps overdue pending requests and returns how many expired.
// Run periodically by the server's maintenance loop; the lazy expiry in
// Get/ListFor keeps reads correct between sweeps.
func (m *ConnectionRequestManager) ExpireStale(ctx context.Context) (int, error) {
	pending, err := m.store.ListPending(ctx)
	if err != nil {
		return 0, err
	}
	now := m.now().UTC()
	expired := 0
	for _, req := range pending {
		if now.After(req.ExpiresAt) {
			if _, err := m.transition(ctx, req, RequestExpired); err != nil {
				if errors.Is(err, ErrRequestState) {
					continue // raced with another transition — fine
				}
				return expired, err
			}
			expired++
		}
	}
	return expired, nil
}

// ListFor returns all requests involving [hash], lazily expiring stale ones.
func (m *ConnectionRequestManager) ListFor(ctx context.Context, hash string) ([]ConnectionRequest, error) {
	reqs, err := m.store.ListFor(ctx, hash)
	if err != nil {
		return nil, err
	}
	out := make([]ConnectionRequest, 0, len(reqs))
	for _, req := range reqs {
		if req.Status == RequestPending && m.now().UTC().After(req.ExpiresAt) {
			expired, err := m.transition(ctx, req, RequestExpired)
			if err != nil {
				return nil, err
			}
			out = append(out, *expired)
			continue
		}
		out = append(out, req)
	}
	return out, nil
}

// transition applies one CAS state change (authorization is enforced by the
// callers — respond/Withdraw — before this point).
func (m *ConnectionRequestManager) transition(ctx context.Context, req ConnectionRequest, to ConnectionRequestStatus) (*ConnectionRequest, error) {
	if req.Status.terminal() {
		return nil, fmt.Errorf("%w: %s is %s", ErrRequestState, req.ID, req.Status)
	}
	req.Status = to
	req.UpdatedAt = m.now().UTC()
	if err := m.store.Update(ctx, req); err != nil {
		if errors.Is(err, ErrRequestState) {
			return nil, ErrRequestState
		}
		return nil, err
	}
	return &req, nil
}

// randomHex returns [n] random bytes hex-encoded.
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}
