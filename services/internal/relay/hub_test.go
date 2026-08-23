package relay

import (
	"context"
	"errors"
	"sync"
	"testing"

	"github.com/coder/websocket"

	"github.com/kankan223/pari/services/proto"
)

// fakePeer is an in-memory Peer used to exercise hub routing.
type fakePeer struct {
	id        string
	failWrite bool

	mu       sync.Mutex
	received []*proto.Envelope
	closed   bool
}

func (f *fakePeer) DeviceID() string { return f.id }

func (f *fakePeer) WriteEnvelope(_ context.Context, env *proto.Envelope) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.failWrite {
		return errors.New("write failed")
	}
	f.received = append(f.received, env)
	return nil
}

func (f *fakePeer) WriteFrame(_ context.Context, _ *proto.ServerFrame) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.failWrite {
		return errors.New("write failed")
	}
	return nil
}

func (f *fakePeer) Close(_ websocket.StatusCode, _ string) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.closed = true
}

func (f *fakePeer) count() int {
	f.mu.Lock()
	defer f.mu.Unlock()
	return len(f.received)
}

func (f *fakePeer) last() *proto.Envelope {
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.received) == 0 {
		return nil
	}
	return f.received[len(f.received)-1]
}

func testEnvelope(sender, recipient, msgID, deviceID string) *proto.Envelope {
	return &proto.Envelope{
		MsgId:          msgID,
		SenderHash:     sender,
		RecipientHash:  recipient,
		Ciphertext:     []byte("ciphertext-bytes"),
		SentAtMs:       1700000000000,
		SenderDeviceId: deviceID,
	}
}

func TestHubFanOutToAllRecipientDevices(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	d1, d2, d3 := &fakePeer{id: "d1"}, &fakePeer{id: "d2"}, &fakePeer{id: "d3"}
	h.Register(recipientA, "d1", d1)
	h.Register(recipientA, "d2", d2)
	h.Register(recipientA, "d3", d3)

	res, err := h.Deliver(ctx, testEnvelope("senderX", recipientA, "m1", "devX"))
	if err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	if res.DeliveredTo != 3 || res.Queued {
		t.Fatalf("Deliver() = %+v, want 3 deliveries, no queue", res)
	}
	for _, d := range []*fakePeer{d1, d2, d3} {
		if d.count() != 1 || d.last().MsgId != "m1" {
			t.Fatalf("device %s received %d msgs, want m1 once", d.id, d.count())
		}
	}
	if n, _ := q.Len(ctx, recipientA); n != 0 {
		t.Fatalf("offline queue has %d entries, want 0", n)
	}
}

func TestHubOfflineRecipientGoesToQueue(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	res, err := h.Deliver(ctx, testEnvelope("senderX", offlineRecipient, "m1", "devX"))
	if err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	if !res.Queued || res.DeliveredTo != 0 || res.EntryID == "" {
		t.Fatalf("Deliver() = %+v, want queued with entry", res)
	}
	if n, _ := q.Len(ctx, offlineRecipient); n != 1 {
		t.Fatalf("offline queue len = %d, want 1", n)
	}
}

func TestHubSelfSyncExcludesSendingDevice(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	senderD1 := &fakePeer{id: "d1"} // the device sending the message
	senderD2 := &fakePeer{id: "d2"} // the sender's other device (sync target)
	h.Register("senderX", "d1", senderD1)
	h.Register("senderX", "d2", senderD2)

	env := testEnvelope("senderX", offlineRecipient, "m1", "d1")
	res, err := h.Deliver(ctx, env)
	if err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	// Recipient is offline → queued; sender's other device still gets a copy.
	if !res.Queued {
		t.Fatal("want queued for offline recipient")
	}
	if res.DeliveredTo != 1 {
		t.Fatalf("DeliveredTo = %d, want 1 (sender sync device)", res.DeliveredTo)
	}
	if senderD2.count() != 1 || senderD2.last().MsgId != "m1" {
		t.Fatal("sender's other device did not receive the sync copy")
	}
	if senderD1.count() != 0 {
		t.Fatal("sending device received its own message (echo)")
	}
}

func TestHubDeadPeerEvictedAndQueued(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	dead := &fakePeer{id: "d1", failWrite: true}
	h.Register(recipientA, "d1", dead)

	res, err := h.Deliver(ctx, testEnvelope("senderX", recipientA, "m1", "devX"))
	if err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	if !res.Queued {
		t.Fatal("want fallback to queue when the only recipient device is dead")
	}
	if h.OnlineCount() != 0 {
		t.Fatal("dead peer was not evicted")
	}
	dead.mu.Lock()
	closed := dead.closed
	dead.mu.Unlock()
	if !closed {
		t.Fatal("dead peer was not closed")
	}
}

func TestHubReconnectEvictsOldConnection(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)

	old := &fakePeer{id: "d1"}
	h.Register(recipientA, "d1", old)
	h.Register(recipientA, "d1", &fakePeer{id: "d1"}) // reconnect

	old.mu.Lock()
	closed := old.closed
	old.mu.Unlock()
	if !closed {
		t.Fatal("old connection not evicted on reconnect")
	}
	if h.DeviceCount(recipientA) != 1 {
		t.Fatalf("DeviceCount = %d, want 1", h.DeviceCount(recipientA))
	}
}

func TestHubUnregisterStopsRouting(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	p := &fakePeer{id: "d1"}
	h.Register(recipientA, "d1", p)
	h.Unregister(recipientA, "d1", p)

	res, err := h.Deliver(ctx, testEnvelope("senderX", recipientA, "m1", "devX"))
	if err != nil {
		t.Fatalf("Deliver() error = %v", err)
	}
	if !res.Queued || p.count() != 0 {
		t.Fatalf("unregistered peer still routed: %+v", res)
	}
}

func TestHubAckByMsgIDPurgesQueue(t *testing.T) {
	q, _ := newTestQueue(t)
	h := NewHub(q)
	ctx := context.Background()

	// Recipient offline → two messages queued.
	if _, err := h.Deliver(ctx, testEnvelope("senderX", recipientA, "m1", "devX")); err != nil {
		t.Fatal(err)
	}
	if _, err := h.Deliver(ctx, testEnvelope("senderY", recipientA, "m2", "devY")); err != nil {
		t.Fatal(err)
	}

	// Client acks m1 only → m2 must survive.
	if err := h.Ack(ctx, recipientA, "m1"); err != nil {
		t.Fatalf("Ack() error = %v", err)
	}
	msgs, err := q.ReadPending(ctx, recipientA, 10)
	if err != nil {
		t.Fatalf("ReadPending() error = %v", err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "m2" {
		t.Fatalf("after ack m1: %+v, want only m2", msgs)
	}

	// Ack m2 → queue purged (stream key gone).
	if err := h.Ack(ctx, recipientA, "m2"); err != nil {
		t.Fatalf("Ack() error = %v", err)
	}
	if n, _ := q.Len(ctx, recipientA); n != 0 {
		t.Fatalf("queue len after full drain = %d, want 0", n)
	}
	if _, err := q.ReadPending(ctx, recipientA, 10); !errors.Is(err, ErrQueueEmpty) {
		t.Fatalf("ReadPending after purge = %v, want ErrQueueEmpty", err)
	}
}
