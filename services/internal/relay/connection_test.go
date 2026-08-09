package relay

import (
	"bytes"
	"context"
	"errors"
	"log/slog"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/coder/websocket"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
	"github.com/kankan223/pari/services/internal/logging"
	"github.com/kankan223/pari/services/proto"
)

// stubAuthenticator maps access tokens to blind_hash_ids.
type stubAuthenticator struct {
	tokens map[string]string
}

func (a *stubAuthenticator) Authenticate(_ context.Context, token string) (string, error) {
	if hash, ok := a.tokens[token]; ok {
		return hash, nil
	}
	return "", errors.New("relay: invalid token")
}

// syncBuf is a mutex-guarded bytes.Buffer: the server writes logs from its
// own goroutines while tests read the buffer concurrently.
type syncBuf struct {
	mu  sync.Mutex
	buf bytes.Buffer
}

func (b *syncBuf) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.Write(p)
}

func (b *syncBuf) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.buf.String()
}

// wsTestEnv is a full relay server on an httptest listener.
type wsTestEnv struct {
	ts     *httptest.Server
	hub    *Hub
	queue  *RedisOfflineQueue
	mr     *miniredis.Miniredis
	logBuf *syncBuf
}

func newWSTestEnv(t *testing.T) *wsTestEnv {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	queue := NewRedisOfflineQueue(rdb, testQueueTTL)
	hub := NewHub(queue)
	auth := &stubAuthenticator{tokens: map[string]string{
		"token-alice": alice,
		"token-bob":   bob,
		"token-carol": "3333333333333333333333333333333333333333333333333333333333333333",
	}}
	logBuf := &syncBuf{}
	// The real shared redacting logger, matching production wiring — the
	// no-phone-in-logs test then exercises the redactor, not just the
	// relay's own logging discipline.
	logger := logging.NewRedactingLogger(logBuf, slog.LevelInfo)
	srv := NewServer(ServerOptions{
		Hub:           hub,
		Authenticator: auth,
		Requests:      NewConnectionRequestManager(NewMemRequestStore(), &recordingPublisher{}, time.Hour),
		Logger:        logger,
		PingInterval:  time.Second, // short for tests
		PongTimeout:   500 * time.Millisecond,
		QueueTTL:      testQueueTTL,
	})
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return &wsTestEnv{ts: ts, hub: hub, queue: queue, mr: mr, logBuf: logBuf}
}

// dial opens a WS connection to the relay's upgrade endpoint.
//
// and torn down via t.Cleanup, which the analyzer cannot see.
//
//nolint:bodyclose // the returned conn is deliberately kept open for the test
func (e *wsTestEnv) dial(t *testing.T) *websocket.Conn {
	t.Helper()
	wsURL := "ws" + strings.TrimPrefix(e.ts.URL, "http") + "/v1/relay/ws"
	c, _, err := websocket.Dial(context.Background(), wsURL, nil)
	if err != nil {
		t.Fatalf("websocket.Dial: %v", err)
	}
	t.Cleanup(func() { _ = c.CloseNow() })
	return c
}

func wsAuth(t *testing.T, c *websocket.Conn, token, deviceID string) *proto.AuthAck {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := writeFrame(ctx, c, &proto.ClientFrame{Payload: &proto.ClientFrame_Auth{
		Auth: &proto.AuthRequest{AccessToken: token, DeviceId: deviceID},
	}}); err != nil {
		t.Fatalf("write auth frame: %v", err)
	}
	var frame proto.ServerFrame
	if err := readFrame(ctx, c, &frame); err != nil {
		t.Fatalf("read auth ack: %v", err)
	}
	return frame.GetAuthAck()
}

func wsSendEnvelope(t *testing.T, c *websocket.Conn, env *proto.Envelope) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := writeFrame(ctx, c, &proto.ClientFrame{Payload: &proto.ClientFrame_Envelope{
		Envelope: env,
	}}); err != nil {
		t.Fatalf("write envelope: %v", err)
	}
}

// wsReadFrame reads the next server frame with a deadline.
func wsReadFrame(t *testing.T, c *websocket.Conn) *proto.ServerFrame {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	var frame proto.ServerFrame
	if err := readFrame(ctx, c, &frame); err != nil {
		t.Fatalf("read server frame: %v", err)
	}
	return &frame
}

func TestWSAuthSuccess(t *testing.T) {
	e := newWSTestEnv(t)
	c := e.dial(t)

	ack := wsAuth(t, c, "token-alice", "dev-1")
	if ack == nil || !ack.Authenticated || ack.BlindHashId != alice {
		t.Fatalf("AuthAck = %+v, want authenticated alice", ack)
	}
}

func TestWSAuthFailureRejected(t *testing.T) {
	e := newWSTestEnv(t)
	c := e.dial(t)

	ack := wsAuth(t, c, "bad-token", "dev-1")
	if ack == nil || ack.Authenticated {
		t.Fatalf("AuthAck = %+v, want authenticated=false", ack)
	}
	// The connection must be closed after a failed auth.
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	var frame proto.ServerFrame
	if err := readFrame(ctx, c, &frame); err == nil {
		t.Fatal("expected connection close after failed auth, got a frame")
	}
}

func TestWSFirstFrameMustBeAuth(t *testing.T) {
	e := newWSTestEnv(t)
	c := e.dial(t)

	// First frame is an envelope, not auth → connection rejected.
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := writeFrame(ctx, c, &proto.ClientFrame{Payload: &proto.ClientFrame_Envelope{
		Envelope: &proto.Envelope{MsgId: "m", RecipientHash: bob},
	}}); err != nil {
		t.Fatalf("write: %v", err)
	}
	time.Sleep(100 * time.Millisecond)
	if e.hub.OnlineCount() != 0 {
		t.Fatal("peer registered without auth")
	}
}

// TestWSRouteOnlineEnvelope is the Task 4.4 VERIFY for WebSocket message
// routing: an envelope sent by one authenticated client is delivered to the
// other's live device, with the sender identity server-overridden.
func TestWSRouteOnlineEnvelope(t *testing.T) {
	e := newWSTestEnv(t)
	sender := e.dial(t)
	recipient := e.dial(t)
	wsAuth(t, sender, "token-alice", "alice-phone")
	wsAuth(t, recipient, "token-bob", "bob-phone")

	ciphertext := []byte{0xDE, 0xAD, 0xBE, 0xEF, 0x01, 0x02, 0x03}
	wsSendEnvelope(t, sender, &proto.Envelope{
		MsgId:          "uuid-1",
		SenderHash:     "spoofed-hash", // MUST be overridden by the server
		RecipientHash:  bob,
		Ciphertext:     ciphertext,
		SentAtMs:       1700000000000,
		SenderDeviceId: "spoofed-device",
	})

	frame := wsReadFrame(t, recipient)
	env := frame.GetEnvelope()
	if env == nil {
		t.Fatalf("recipient got %T, want envelope", frame.Payload)
	}
	if env.MsgId != "uuid-1" {
		t.Fatalf("MsgId = %q", env.MsgId)
	}
	// SECURITY: sender identity is the authenticated token's hash, never the
	// client-supplied value.
	if env.SenderHash != alice {
		t.Fatalf("SenderHash = %q, want authenticated %q (spoof blocked)", env.SenderHash, alice)
	}
	if env.SenderDeviceId != "alice-phone" {
		t.Fatalf("SenderDeviceId = %q, want alice-phone", env.SenderDeviceId)
	}
	if !bytes.Equal(env.Ciphertext, ciphertext) {
		t.Fatalf("ciphertext corrupted: %x", env.Ciphertext)
	}
}

func TestWSMultiDeviceFanOut(t *testing.T) {
	e := newWSTestEnv(t)
	sender := e.dial(t)
	bobPhone := e.dial(t)
	bobDesktop := e.dial(t)
	wsAuth(t, sender, "token-alice", "a1")
	wsAuth(t, bobPhone, "token-bob", "b1")
	wsAuth(t, bobDesktop, "token-bob", "b2")

	wsSendEnvelope(t, sender, &proto.Envelope{
		MsgId:         "fanout-1",
		RecipientHash: bob,
		Ciphertext:    []byte("x"),
	})

	f1 := wsReadFrame(t, bobPhone)
	f2 := wsReadFrame(t, bobDesktop)
	if f1.GetEnvelope() == nil || f2.GetEnvelope() == nil {
		t.Fatalf("both bob devices must receive the envelope: %T, %T", f1.Payload, f2.Payload)
	}
	if f1.GetEnvelope().MsgId != "fanout-1" || f2.GetEnvelope().MsgId != "fanout-1" {
		t.Fatalf("fan-out mismatch: %q vs %q", f1.GetEnvelope().MsgId, f2.GetEnvelope().MsgId)
	}
}

// TestWSOfflineQueueDrainAndAck is the end-to-end offline flow: message
// queued while the recipient is away, delivered on reconnect, and purged on
// the client's DeliveryAck.
func TestWSOfflineQueueDrainAndAck(t *testing.T) {
	e := newWSTestEnv(t)
	sender := e.dial(t)
	wsAuth(t, sender, "token-alice", "a1")

	// Recipient offline → message must be persisted to the stream.
	wsSendEnvelope(t, sender, &proto.Envelope{
		MsgId:         "offline-1",
		RecipientHash: bob,
		Ciphertext:    []byte("queued-ciphertext"),
	})
	deadline := time.Now().Add(2 * time.Second)
	for {
		n, _ := e.queue.Len(context.Background(), bob)
		if n == 1 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("message not queued for offline recipient")
		}
		time.Sleep(10 * time.Millisecond)
	}

	// Recipient connects → the queued envelope is drained to them.
	recipient := e.dial(t)
	wsAuth(t, recipient, "token-bob", "b1")
	frame := wsReadFrame(t, recipient)
	env := frame.GetEnvelope()
	if env == nil || env.MsgId != "offline-1" {
		t.Fatalf("drain delivered %T %q, want envelope offline-1", frame.Payload, env.GetMsgId())
	}
	if string(env.Ciphertext) != "queued-ciphertext" {
		t.Fatalf("drained ciphertext corrupted")
	}

	// Client acks → entry purged and the stream deleted (queue purge).
	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := writeFrame(ctx, recipient, &proto.ClientFrame{Payload: &proto.ClientFrame_Ack{
		Ack: &proto.DeliveryAck{MsgId: "offline-1"},
	}}); err != nil {
		t.Fatalf("write ack: %v", err)
	}
	deadline = time.Now().Add(2 * time.Second)
	for {
		n, _ := e.queue.Len(context.Background(), bob)
		if n == 0 {
			break
		}
		if time.Now().After(deadline) {
			t.Fatal("queue not purged after delivery ack")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if e.mr.Exists(cache.NSMsgQueue + ":" + bob) {
		t.Fatal("stream key still exists after ack purge")
	}
}

// TestWSDrainTrimsExpiredEntries verifies the 30-day TTL is enforced at
// delivery time: an entry older than the retention window is dropped when
// the recipient reconnects, while a fresh entry is delivered.
func TestWSDrainTrimsExpiredEntries(t *testing.T) {
	e := newWSTestEnv(t)
	ctx := context.Background()

	// Plant an expired entry directly with an ancient stream ID.
	oldID := formatStreamID(time.Now().UTC().Add(-31 * 24 * time.Hour))
	key, err := cache.MsgQueueKey(bob)
	if err != nil {
		t.Fatal(err)
	}
	if err := e.queue.rdb.XAdd(ctx, &redis.XAddArgs{
		Stream: key,
		ID:     oldID,
		Values: map[string]any{"msg_id": "ancient", "sender_hash": alice, "ciphertext": "old"},
	}).Err(); err != nil {
		t.Fatalf("seed old entry: %v", err)
	}
	// Enqueue a fresh message through the normal path.
	if _, err := e.queue.Enqueue(ctx, bob, QueuedMessage{
		MsgID: "fresh-1", SenderHash: alice, Ciphertext: []byte("new"),
	}); err != nil {
		t.Fatalf("enqueue fresh: %v", err)
	}

	// Bob reconnects → only the fresh message is drained.
	recipient := e.dial(t)
	wsAuth(t, recipient, "token-bob", "b1")
	frame := wsReadFrame(t, recipient)
	env := frame.GetEnvelope()
	if env == nil || env.MsgId != "fresh-1" {
		t.Fatalf("drain delivered %v, want only fresh-1 (expired entry trimmed)", env)
	}
	n, _ := e.queue.Len(ctx, bob)
	if n != 1 {
		t.Fatalf("queue len = %d, want 1 (ancient trimmed, fresh awaiting ack)", n)
	}
}

func TestWSPingKeepsConnectionAlive(t *testing.T) {
	// The server pings every 1s; a healthy coder/websocket client auto-pongs,
	// so the connection must survive several heartbeat cycles.
	e := newWSTestEnv(t)
	c := e.dial(t)
	wsAuth(t, c, "token-alice", "a1")

	time.Sleep(2600 * time.Millisecond) // > 2 ping cycles
	if e.hub.OnlineCount() != 1 {
		t.Fatalf("OnlineCount = %d, want 1 (client dropped by heartbeat)", e.hub.OnlineCount())
	}
}

func TestWSSecondAuthFrameCloses(t *testing.T) {
	e := newWSTestEnv(t)
	c := e.dial(t)
	wsAuth(t, c, "token-alice", "a1")

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	if err := writeFrame(ctx, c, &proto.ClientFrame{Payload: &proto.ClientFrame_Auth{
		Auth: &proto.AuthRequest{AccessToken: "token-alice", DeviceId: "a1"},
	}}); err != nil {
		t.Fatalf("write second auth: %v", err)
	}

	// The peer must be evicted (connection closed → unregistered).
	deadline := time.Now().Add(2 * time.Second)
	for e.hub.OnlineCount() != 0 {
		if time.Now().After(deadline) {
			t.Fatal("peer not evicted after protocol violation")
		}
		time.Sleep(10 * time.Millisecond)
	}
}

// TestWSNoPhoneInLogs is part of the security checkpoint: relay logs must
// never contain phone numbers (the relay should never see one, but the log
// redaction is verified end to end by searching the captured buffer).
func TestWSNoPhoneInLogs(t *testing.T) {
	e := newWSTestEnv(t)
	c := e.dial(t)
	wsAuth(t, c, "token-alice", "a1")
	wsSendEnvelope(t, c, &proto.Envelope{
		MsgId:         "m1",
		RecipientHash: bob,
		Ciphertext:    []byte("+14155552671-and-more"),
	})
	time.Sleep(200 * time.Millisecond)

	raw := e.logBuf.String()
	if strings.Contains(raw, "14155552671") {
		t.Fatal("phone-like digits leaked into relay logs")
	}
}
