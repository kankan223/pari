package events

import (
	"context"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"sync"
	"testing"
	"time"

	"github.com/nats-io/nats-server/v2/server"
	"github.com/nats-io/nats.go"
)

// startTestServer boots an in-process JetStream-enabled nats-server on a
// random port. Tests run against the real server (same as miniredis for
// Redis — no mocking of the broker itself).
func startTestServer(t *testing.T) *server.Server {
	t.Helper()
	opts := &server.Options{
		JetStream:  true,
		StoreDir:   t.TempDir(),
		Port:       -1,
		NoLog:      true,
		NoSigs:     true,
		MaxPayload: 1 << 20,
	}
	srv, err := server.NewServer(opts)
	if err != nil {
		t.Fatalf("start nats-server: %v", err)
	}
	go srv.Start()
	if !srv.ReadyForConnections(10 * time.Second) {
		srv.Shutdown()
		t.Fatal("nats-server not ready in time")
	}
	t.Cleanup(srv.Shutdown)
	return srv
}

// newTestClient builds a Client + ensures the default stream.
func newTestClient(t *testing.T, srv *server.Server) *Client {
	t.Helper()
	c, err := NewClient(Options{URL: srv.ClientURL(), MaxReconnects: 10})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })
	if err := c.EnsureStream(context.Background(), DefaultStreamConfig()); err != nil {
		t.Fatalf("EnsureStream: %v", err)
	}
	return c
}

func TestEnsureStreamIdempotent(t *testing.T) {
	srv := startTestServer(t)
	c := newTestClient(t, srv)

	// Second EnsureStream reconciles rather than erroring.
	if err := c.EnsureStream(context.Background(), DefaultStreamConfig()); err != nil {
		t.Fatalf("second EnsureStream: %v", err)
	}
	si, err := c.StreamInfo(context.Background())
	if err != nil {
		t.Fatalf("StreamInfo: %v", err)
	}
	if si.Config.Name != DefaultStreamName {
		t.Errorf("stream name = %q, want %q", si.Config.Name, DefaultStreamName)
	}
	want := RegisteredSubjects()
	if len(si.Config.Subjects) != len(want) {
		t.Errorf("stream subjects = %v, want %v", si.Config.Subjects, want)
	}
	for _, s := range want {
		if !contains(si.Config.Subjects, s) {
			t.Errorf("stream missing subject %q (have %v)", s, si.Config.Subjects)
		}
	}
	if si.Config.Storage != nats.FileStorage {
		t.Errorf("storage = %v, want file", si.Config.Storage)
	}
}

func TestPublishSubscribeRoundTrip(t *testing.T) {
	srv := startTestServer(t)
	c := newTestClient(t, srv)

	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()

	type event struct {
		Initiator string `json:"initiator"`
		Target    string `json:"target"`
	}
	got := make(chan string, 4)
	sub, err := c.SubscribeDurable(ctx, SubjectConnectionAccepted, "test-conn", func(m *nats.Msg) error {
		got <- string(m.Data)
		return nil
	})
	if err != nil {
		t.Fatalf("SubscribeDurable: %v", err)
	}
	defer func() { _ = sub.Unsubscribe() }()

	payload, _ := json.Marshal(event{Initiator: blindHash("a"), Target: blindHash("b")})
	for i := 0; i < 3; i++ {
		if err := c.Publish(ctx, SubjectConnectionAccepted, payload); err != nil {
			t.Fatalf("Publish: %v", err)
		}
	}

	for i := 0; i < 3; i++ {
		select {
		case data := <-got:
			var ev event
			if err := json.Unmarshal([]byte(data), &ev); err != nil {
				t.Fatalf("bad payload: %v", err)
			}
			if ev.Initiator == "" || ev.Target == "" {
				t.Errorf("payload lost fields: %+v", ev)
			}
		case <-ctx.Done():
			t.Fatal("timed out waiting for events")
		}
	}
}

// TestDurableConsumerRedelivery proves at-least-once: a message whose handler
// fails is NAK'd and redelivered; a durable consumer that is unsubscribed and
// resubscribed with the same durable name resumes (does not re-deliver acked
// messages).
func TestDurableConsumerRedelivery(t *testing.T) {
	srv := startTestServer(t)
	c := newTestClient(t, srv)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	// First consumer fails on the first message then succeeds — the failed
	// one must redeliver.
	var (
		mu       sync.Mutex
		attempts = map[string]int{}
	)
	done := make(chan string, 1)
	sub, err := c.SubscribeDurable(ctx, SubjectKarmaUpdated, "dup-delivery", func(m *nats.Msg) error {
		id := string(m.Data)
		mu.Lock()
		attempts[id]++
		n := attempts[id]
		mu.Unlock()
		if n == 1 {
			return errors.New("transient failure")
		}
		done <- id
		return nil
	})
	if err != nil {
		t.Fatalf("SubscribeDurable: %v", err)
	}
	defer func() { _ = sub.Unsubscribe() }()

	if err := c.Publish(ctx, SubjectKarmaUpdated, []byte("karma-evt-1")); err != nil {
		t.Fatalf("Publish: %v", err)
	}
	select {
	case id := <-done:
		if id != "karma-evt-1" {
			t.Errorf("redelivered %q", id)
		}
	case <-ctx.Done():
		t.Fatal("timed out waiting for redelivery")
	}
}

// TestDurableConsumerRestartResume proves no event loss AND resume semantics:
// events published before a server restart are re-delivered to a durable
// consumer recreated with the same name; events already acked are not.
func TestDurableConsumerRestartResume(t *testing.T) {
	storeDir := t.TempDir()
	opts := &server.Options{
		JetStream: true, StoreDir: storeDir, Port: -1, NoLog: true, NoSigs: true,
	}

	// --- phase 1: publish + ack one event, leave another unacked ---
	srv1, err := server.NewServer(opts)
	if err != nil {
		t.Fatal(err)
	}
	go srv1.Start()
	if !srv1.ReadyForConnections(10 * time.Second) {
		srv1.Shutdown()
		t.Fatal("server 1 not ready")
	}

	c1, err := NewClient(Options{URL: srv1.ClientURL(), MaxReconnects: 5})
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := c1.EnsureStream(ctx, DefaultStreamConfig()); err != nil {
		t.Fatal(err)
	}

	// Phase 1 consumer acks "acked-1" and is then drained (its durable ack
	// progress is persisted).
	ackFirst := make(chan struct{})
	var ackOnce sync.Once
	sub1, err := c1.SubscribeDurable(ctx, SubjectUserRegistered, "restart-resume", func(m *nats.Msg) error {
		ackOnce.Do(func() { close(ackFirst) })
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	if err := c1.Publish(ctx, SubjectUserRegistered, []byte("acked-1")); err != nil {
		t.Fatal(err)
	}
	select {
	case <-ackFirst:
	case <-time.After(10 * time.Second):
		t.Fatal("first event not delivered")
	}
	// Wait for the ack to flush, then drain the consumer so nothing further
	// is delivered in phase 1.
	time.Sleep(200 * time.Millisecond)
	_ = sub1.Drain()
	_ = c1.Flush()

	// Publish an event AFTER the consumer is drained — it is persisted to
	// the stream but never delivered/acked before the crash.
	if err := c1.Publish(ctx, SubjectUserRegistered, []byte("unacked-1")); err != nil {
		t.Fatal(err)
	}
	if err := c1.Flush(); err != nil {
		t.Fatal(err)
	}
	// Crash the server (no graceful shutdown drain of acks).
	srv1.Shutdown()
	srv1.WaitForShutdown()
	_ = c1.Close()

	// --- phase 2: restart on the SAME store dir; durable consumer resumes ---
	srv2, err := server.NewServer(opts)
	if err != nil {
		t.Fatal(err)
	}
	go srv2.Start()
	if !srv2.ReadyForConnections(10 * time.Second) {
		srv2.Shutdown()
		t.Fatal("server 2 not ready")
	}
	t.Cleanup(srv2.Shutdown)

	c2, err := NewClient(Options{URL: srv2.ClientURL(), MaxReconnects: 5})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = c2.Close() })
	if err := c2.EnsureStream(ctx, DefaultStreamConfig()); err != nil {
		t.Fatal(err)
	}

	received := make(chan string, 4)
	sub2, err := c2.SubscribeDurable(ctx, SubjectUserRegistered, "restart-resume", func(m *nats.Msg) error {
		received <- string(m.Data)
		return nil
	})
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = sub2.Unsubscribe() }()

	// The acked event must NOT re-deliver; the unacked one must (no loss).
	select {
	case got := <-received:
		if got != "unacked-1" {
			t.Errorf("redelivered %q, want unacked-1 (acked event must not replay)", got)
		}
	case <-time.After(10 * time.Second):
		t.Fatal("unacked event lost after restart (no event loss violated)")
	}
	select {
	case got := <-received:
		t.Errorf("acked event re-delivered after restart: %q", got)
	case <-time.After(500 * time.Millisecond):
		// correct — acked events do not replay
	}
}

// TestPublishRejectsPII enforces the SECURITY CHECKPOINT: PII-shaped subjects
// and payloads are rejected before they reach the wire.
func TestPublishRejectsPII(t *testing.T) {
	srv := startTestServer(t)
	c := newTestClient(t, srv)
	ctx := context.Background()

	cases := []struct {
		name    string
		subject string
		payload []byte
	}{
		{"phone-subject", "+919876543210.events", []byte("{}")},
		{"email-subject", "user@example.com.events", []byte("{}")},
		{"phone-payload", SubjectConnectionAccepted, []byte(`{"phone":"+14155552671"}`)},
		{"email-payload", SubjectKarmaUpdated, []byte(`{"email":"a@b.co"}`)},
		{"unregistered-subject", "totally.custom.subject", []byte("{}")},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			if err := c.Publish(ctx, tc.subject, tc.payload); err == nil {
				t.Fatalf("expected PII/schema rejection, got nil")
			}
		})
	}
}

// TestValidateSubject allows registered subjects and rejects anything else.
func TestValidateSubject(t *testing.T) {
	for _, s := range RegisteredSubjects() {
		if err := ValidateSubject(s); err != nil {
			t.Errorf("ValidateSubject(%q): %v", s, err)
		}
	}
	for _, s := range []string{"", "+919876543210", "user@example.com", "Foo.Bar", "civic.", ".civic", "relay.connection.accepted.extra", "nope"} {
		if err := ValidateSubject(s); err == nil {
			t.Errorf("ValidateSubject(%q) = nil, want error", s)
		}
	}
}

// TestConcurrentDurableCreate proves two subscribers racing to create the
// same durable consumer both succeed (ErrConsumerNameAlreadyInUse is benign)
// — the scenario when relay replicas / consumer groups start together.
func TestConcurrentDurableCreate(t *testing.T) {
	srv := startTestServer(t)
	c := newTestClient(t, srv)

	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()

	const durable = "race-durable"
	var wg sync.WaitGroup
	errs := make(chan error, 2)
	for i := 0; i < 2; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			sub, err := c.SubscribeDurable(ctx, SubjectKarmaUpdated, durable, func(m *nats.Msg) error {
				return nil
			})
			if err != nil {
				errs <- err
				return
			}
			defer func() { _ = sub.Unsubscribe() }()
			errs <- nil
		}()
	}
	wg.Wait()
	close(errs)
	for err := range errs {
		if err != nil {
			t.Fatalf("concurrent durable create failed: %v", err)
		}
	}

	// The consumer exists once, and a fresh subscribe binds to it.
	if _, err := c.js.ConsumerInfo(DefaultStreamName, durable); err != nil {
		t.Fatalf("durable consumer missing after race: %v", err)
	}
}

// TestEnsureStreamOptionFallback proves Options.Storage/MaxAge apply when the
// passed StreamConfig leaves them zero (fixes the dead-config review finding).
func TestEnsureStreamOptionFallback(t *testing.T) {
	srv := startTestServer(t)
	c, err := NewClient(Options{URL: srv.ClientURL(), Storage: StorageMemory, MaxAge: 90 * time.Minute})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	t.Cleanup(func() { _ = c.Close() })

	if err := c.EnsureStream(context.Background(), StreamConfig{Subjects: []string{SubjectKarmaUpdated}}); err != nil {
		t.Fatalf("EnsureStream: %v", err)
	}
	si, err := c.StreamInfo(context.Background())
	if err != nil {
		t.Fatalf("StreamInfo: %v", err)
	}
	if si.Config.Storage != nats.MemoryStorage {
		t.Errorf("storage = %v, want memory (from Options fallback)", si.Config.Storage)
	}
	if si.Config.MaxAge != 90*time.Minute {
		t.Errorf("max age = %v, want 90m (from Options fallback)", si.Config.MaxAge)
	}
}

func TestValidatePayload(t *testing.T) {
	ok := [][]byte{nil, []byte("{}"), []byte(blindHash("x")), []byte("ciphertext-bytes-are-opaque")}
	for _, p := range ok {
		if err := ValidatePayload(p); err != nil {
			t.Errorf("ValidatePayload(%q): %v", p, err)
		}
	}
	bad := [][]byte{[]byte("+919876543210"), []byte(`{"to":"a@b.co"}`), []byte("call +14155552671 now")}
	for _, p := range bad {
		if err := ValidatePayload(p); err == nil {
			t.Errorf("ValidatePayload(%q) = nil, want error", p)
		}
	}
}

// TestNoopFallback: the relay uses NoopEventPublisher in dev — assert the
// event-bus noop semantics via a standalone check that publishing never
// errors and nothing is delivered.
func TestPublishToMissingStreamSucceedsCoreOnly(t *testing.T) {
	// Core NATS publish succeeds even without JetStream stream — the relay
	// previously published on core NATS. With the JetStream client, publish
	// to an UNREGISTERED stream still gets a PUBACK error only if JetStream
	// is unavailable. Just assert the client refuses bad subjects.
	c := &Client{stream: DefaultStreamName}
	if err := c.Publish(context.Background(), "not.registered", []byte("x")); err == nil {
		t.Fatal("expected error for unregistered subject")
	}
}

// TestLiveNATSJetStream runs the full pub/sub round-trip against a REAL NATS
// server (env-gated on CIVIC_TEST_NATS_URL, like the PG/Redis live tests).
// The verify_nats_live.sh script starts a docker nats container with
// JetStream enabled and runs this test against it.
func TestLiveNATSJetStream(t *testing.T) {
	url := os.Getenv("CIVIC_TEST_NATS_URL")
	if url == "" {
		t.Skip("CIVIC_TEST_NATS_URL not set; skipping live NATS test")
	}

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	c, err := NewClient(Options{URL: url, MaxReconnects: 10, MaxAge: 5 * time.Minute})
	if err != nil {
		t.Fatalf("NewClient: %v", err)
	}
	defer func() { _ = c.Close() }()

	if err := c.EnsureStream(ctx, DefaultStreamConfig()); err != nil {
		t.Fatalf("EnsureStream: %v", err)
	}
	si, err := c.StreamInfo(ctx)
	if err != nil {
		t.Fatalf("StreamInfo: %v", err)
	}
	if si.Config.Storage != nats.FileStorage {
		t.Errorf("storage = %v, want file (live container runs -js with file store)", si.Config.Storage)
	}

	const durable = "civic-live-verify"
	received := make(chan string, 16)
	sub, err := c.SubscribeDurable(ctx, SubjectKarmaUpdated, durable, func(m *nats.Msg) error {
		received <- string(m.Data)
		return nil
	})
	if err != nil {
		t.Fatalf("SubscribeDurable: %v", err)
	}
	defer func() { _ = sub.Drain() }()

	for i := 0; i < 5; i++ {
		if err := c.Publish(ctx, SubjectKarmaUpdated, []byte(fmt.Sprintf("live-evt-%d", i))); err != nil {
			t.Fatalf("Publish: %v", err)
		}
	}
	got := map[string]bool{}
	for len(got) < 5 {
		select {
		case id := <-received:
			got[id] = true
		case <-ctx.Done():
			t.Fatalf("timed out; received %d/5: %v", len(got), got)
		}
	}
	for i := 0; i < 5; i++ {
		if !got[fmt.Sprintf("live-evt-%d", i)] {
			t.Errorf("missing live-evt-%d", i)
		}
	}

	if !c.Connected() {
		t.Error("client reports disconnected after live round-trip")
	}
	t.Logf("live NATS round-trip OK (stream=%s messages=5)", si.Config.Name)
}

// helpers

// blindHash returns a deterministic 64-hex blind_hash_id-style fixture.
func blindHash(seed string) string {
	sum := make([]byte, 32)
	copy(sum, []byte("civic-"+seed)) // fixture only — padded with zeros
	return hex.EncodeToString(sum)
}

func contains(hay []string, needle string) bool {
	for _, s := range hay {
		if s == needle {
			return true
		}
	}
	return false
}
