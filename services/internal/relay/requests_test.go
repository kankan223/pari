package relay

import (
	"context"
	"encoding/json"
	"errors"
	"sync"
	"testing"
	"time"
)

// recordingPublisher captures published events for assertions.
type recordingPublisher struct {
	mu       sync.Mutex
	subjects []string
	payloads [][]byte
}

func (p *recordingPublisher) Publish(_ context.Context, subject string, payload []byte) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.subjects = append(p.subjects, subject)
	p.payloads = append(p.payloads, payload)
	return nil
}

func (p *recordingPublisher) count(subject string) int {
	p.mu.Lock()
	defer p.mu.Unlock()
	n := 0
	for _, s := range p.subjects {
		if s == subject {
			n++
		}
	}
	return n
}

// newTestRequests builds a manager with a controllable clock.
func newTestRequests(t *testing.T, expiry time.Duration) (*ConnectionRequestManager, *recordingPublisher, *time.Time) {
	t.Helper()
	events := &recordingPublisher{}
	mgr := NewConnectionRequestManager(NewMemRequestStore(), events, expiry)
	now := time.Now()
	mgr.SetClock(func() time.Time { return now })
	return mgr, events, &now
}

// alice/bob are valid 64-hex blind_hash_ids (the stores validate key
// shapes; these must match the blind-hash format).
const alice = "1111111111111111111111111111111111111111111111111111111111111111"
const bob = "2222222222222222222222222222222222222222222222222222222222222222"

func mustJSON(t *testing.T, v any) []byte {
	t.Helper()
	b, err := json.Marshal(v)
	if err != nil {
		t.Fatalf("json.Marshal: %v", err)
	}
	return b
}

func TestCreatePendingRequest(t *testing.T) {
	mgr, _, now := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, err := mgr.Create(ctx, alice, bob)
	if err != nil {
		t.Fatalf("Create() error = %v", err)
	}
	if req.Status != RequestPending || req.InitiatorHash != alice || req.TargetHash != bob {
		t.Fatalf("Create() = %+v", req)
	}
	if !req.ExpiresAt.After(*now) {
		t.Fatal("pending request must carry a future expiry")
	}
}

func TestCreateIdempotentWhilePending(t *testing.T) {
	mgr, _, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	first, err := mgr.Create(ctx, alice, bob)
	if err != nil {
		t.Fatal(err)
	}
	second, err := mgr.Create(ctx, alice, bob)
	if err != nil {
		t.Fatalf("duplicate Create() error = %v", err)
	}
	if first.ID != second.ID {
		t.Fatalf("duplicate pending request got new ID: %s vs %s", first.ID, second.ID)
	}
}

func TestCreateRejectsSelfAndEmpty(t *testing.T) {
	mgr, _, _ := newTestRequests(t, time.Hour)
	ctx := context.Background()

	if _, err := mgr.Create(ctx, alice, alice); err == nil {
		t.Fatal("self-request must error")
	}
	if _, err := mgr.Create(ctx, "", bob); err == nil {
		t.Fatal("empty initiator must error")
	}
}

func TestAcceptFlow(t *testing.T) {
	mgr, events, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)
	accepted, err := mgr.Accept(ctx, req.ID, bob)
	if err != nil {
		t.Fatalf("Accept() error = %v", err)
	}
	if accepted.Status != RequestAccepted {
		t.Fatalf("Accept() status = %s, want accepted", accepted.Status)
	}
	if events.count(ConnectionRequestSubject) != 1 {
		t.Fatal("accept must publish exactly one connection-established event")
	}
	// The event payload must reference only blind hashes (zero-knowledge).
	if string(events.payloads[0]) != string(mustJSON(t, accepted)) {
		t.Fatal("event payload does not match accepted request")
	}
}

func TestRejectAndWithdrawFlows(t *testing.T) {
	mgr, events, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	rej, _ := mgr.Create(ctx, alice, bob)
	rejected, err := mgr.Reject(ctx, rej.ID, bob)
	if err != nil || rejected.Status != RequestRejected {
		t.Fatalf("Reject() = %+v, %v", rejected, err)
	}
	if events.count(ConnectionRequestSubject) != 0 {
		t.Fatal("reject must not publish an accept event")
	}

	wd, _ := mgr.Create(ctx, alice, bob)
	withdrawn, err := mgr.Withdraw(ctx, wd.ID, alice)
	if err != nil || withdrawn.Status != RequestWithdrawn {
		t.Fatalf("Withdraw() = %+v, %v", withdrawn, err)
	}
}

func TestForbiddenActors(t *testing.T) {
	mgr, _, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)

	// Initiator cannot accept or reject.
	if _, err := mgr.Accept(ctx, req.ID, alice); !errors.Is(err, ErrRequestForbidden) {
		t.Fatalf("initiator Accept() = %v, want ErrRequestForbidden", err)
	}
	if _, err := mgr.Reject(ctx, req.ID, alice); !errors.Is(err, ErrRequestForbidden) {
		t.Fatalf("initiator Reject() = %v, want ErrRequestForbidden", err)
	}
	// Target cannot withdraw.
	if _, err := mgr.Withdraw(ctx, req.ID, bob); !errors.Is(err, ErrRequestForbidden) {
		t.Fatalf("target Withdraw() = %v, want ErrRequestForbidden", err)
	}
	// Stranger cannot do anything.
	if _, err := mgr.Accept(ctx, req.ID, "mallory"); !errors.Is(err, ErrRequestForbidden) {
		t.Fatalf("stranger Accept() = %v, want ErrRequestForbidden", err)
	}
}

func TestTerminalStatesAreImmutable(t *testing.T) {
	mgr, _, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)
	if _, err := mgr.Accept(ctx, req.ID, bob); err != nil {
		t.Fatal(err)
	}
	if _, err := mgr.Reject(ctx, req.ID, bob); !errors.Is(err, ErrRequestState) {
		t.Fatalf("transition after accept = %v, want ErrRequestState", err)
	}
	if _, err := mgr.Withdraw(ctx, req.ID, alice); !errors.Is(err, ErrRequestState) {
		t.Fatalf("withdraw after accept = %v, want ErrRequestState", err)
	}
}

func TestConcurrentAcceptSingleWinner(t *testing.T) {
	mgr, events, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)

	const n = 8
	var wg sync.WaitGroup
	var mu sync.Mutex
	accepted := 0
	stateErr := 0
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			_, err := mgr.Accept(ctx, req.ID, bob)
			mu.Lock()
			defer mu.Unlock()
			if err == nil {
				accepted++
			} else if errors.Is(err, ErrRequestState) {
				stateErr++
			}
		}()
	}
	wg.Wait()

	if accepted != 1 {
		t.Fatalf("concurrent accepts succeeded %d times, want exactly 1", accepted)
	}
	if stateErr != n-1 {
		t.Fatalf("concurrent accepts failed with ErrRequestState %d times, want %d", stateErr, n-1)
	}
	if events.count(ConnectionRequestSubject) != 1 {
		t.Fatalf("accept event published %d times, want 1", events.count(ConnectionRequestSubject))
	}
}

func TestLazyExpiryOnGet(t *testing.T) {
	mgr, _, now := newTestRequests(t, time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)

	*now = now.Add(2 * time.Hour) // past the 1h expiry
	got, err := mgr.Get(ctx, req.ID)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if got.Status != RequestExpired {
		t.Fatalf("Get() after expiry = %s, want expired", got.Status)
	}
}

func TestExpireStaleSweeper(t *testing.T) {
	mgr, _, now := newTestRequests(t, time.Hour)
	ctx := context.Background()

	r1, _ := mgr.Create(ctx, alice, bob)
	r2, _ := mgr.Create(ctx, bob, alice)
	r3, _ := mgr.Create(ctx, alice, "carol")

	*now = now.Add(2 * time.Hour)
	n, err := mgr.ExpireStale(ctx)
	if err != nil {
		t.Fatalf("ExpireStale() error = %v", err)
	}
	if n != 3 {
		t.Fatalf("ExpireStale() expired %d, want 3", n)
	}
	for _, id := range []string{r1.ID, r2.ID, r3.ID} {
		got, err := mgr.Get(ctx, id)
		if err != nil || got.Status != RequestExpired {
			t.Fatalf("request %s after sweep = %+v, %v", id, got, err)
		}
	}
	// A second sweep must be a no-op.
	if n, _ := mgr.ExpireStale(ctx); n != 0 {
		t.Fatalf("second sweep expired %d, want 0", n)
	}
}

func TestListForIncludesBothParties(t *testing.T) {
	mgr, _, _ := newTestRequests(t, 30*24*time.Hour)
	ctx := context.Background()

	req, _ := mgr.Create(ctx, alice, bob)

	aliceReqs, err := mgr.ListFor(ctx, alice)
	if err != nil || len(aliceReqs) != 1 || aliceReqs[0].ID != req.ID {
		t.Fatalf("ListFor(alice) = %+v, %v", aliceReqs, err)
	}
	bobReqs, _ := mgr.ListFor(ctx, bob)
	if len(bobReqs) != 1 || bobReqs[0].ID != req.ID {
		t.Fatalf("ListFor(bob) = %+v", bobReqs)
	}
	// A terminal request no longer counts toward dedupe (new request allowed).
	_, _ = mgr.Reject(ctx, req.ID, bob)
	again, err := mgr.Create(ctx, alice, bob)
	if err != nil || again.ID == req.ID {
		t.Fatalf("recreate after reject = %+v, %v", again, err)
	}
}
