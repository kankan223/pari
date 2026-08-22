package relay

import (
	"bytes"
	"context"
	"encoding/hex"
	"errors"
	"strconv"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
)

const testQueueTTL = 30 * 24 * time.Hour

// testHash returns a valid 64-hex blind_hash_id (the queue store validates
// key shapes since Task 4.6).
func testHash(seed byte) string {
	b := bytes.Repeat([]byte{seed}, 32)
	dst := make([]byte, hex.EncodedLen(len(b)))
	hex.Encode(dst, b)
	return string(dst)
}

var (
	recipientA       = testHash(0xAA)
	recipientH       = testHash(0x11)
	hashA            = testHash(0xAB)
	hashB            = testHash(0xBB)
	offlineRecipient = testHash(0x0F)
)

func newTestQueue(t *testing.T) (*RedisOfflineQueue, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	return NewRedisOfflineQueue(cache.WrapRedis(rdb), testQueueTTL), mr
}

func TestQueueEnqueueReadOldestFirst(t *testing.T) {
	q, _ := newTestQueue(t)
	ctx := context.Background()

	for i := 0; i < 3; i++ {
		if _, err := q.Enqueue(ctx, recipientA, QueuedMessage{
			MsgID:      "msg-" + string(rune('a'+i)),
			SenderHash: "senderX",
			Ciphertext: []byte{byte(i), 0xDE, 0xAD},
			SentAtMS:   time.Now().UnixMilli(),
		}); err != nil {
			t.Fatalf("Enqueue() error = %v", err)
		}
	}

	n, err := q.Len(ctx, recipientA)
	if err != nil || n != 3 {
		t.Fatalf("Len() = %d, %v; want 3", n, err)
	}

	msgs, err := q.ReadPending(ctx, recipientA, 10)
	if err != nil {
		t.Fatalf("ReadPending() error = %v", err)
	}
	if len(msgs) != 3 {
		t.Fatalf("ReadPending() len = %d, want 3", len(msgs))
	}
	// Oldest first.
	if msgs[0].MsgID != "msg-a" || msgs[2].MsgID != "msg-c" {
		t.Fatalf("ReadPending() order = %v, want msg-a..msg-c", msgs)
	}
	// Ciphertext round-trips byte-identically (opaque pass-through).
	if string(msgs[0].Ciphertext) != "\x00\xde\xad" || string(msgs[1].Ciphertext) != "\x01\xde\xad" {
		t.Fatalf("ciphertext corrupted: % x", msgs[0].Ciphertext)
	}
	// Sender hash survives (needed for receipts + audit).
	if msgs[0].SenderHash != "senderX" {
		t.Fatalf("sender_hash = %q, want senderX", msgs[0].SenderHash)
	}
}

func TestQueueAckPurgesWhenDrained(t *testing.T) {
	q, mr := newTestQueue(t)
	ctx := context.Background()

	entry, err := q.Enqueue(ctx, recipientA, QueuedMessage{MsgID: "m1", SenderHash: "s", Ciphertext: []byte("x")})
	if err != nil {
		t.Fatalf("Enqueue() error = %v", err)
	}
	if err := q.Ack(ctx, recipientA, entry); err != nil {
		t.Fatalf("Ack() error = %v", err)
	}

	// Queue drained → the stream key must be gone (purge).
	if mr.Exists(cache.NSMsgQueue + ":" + recipientA) {
		t.Fatal("stream key still exists after queue drained")
	}
	n, _ := q.Len(ctx, recipientA)
	if n != 0 {
		t.Fatalf("Len() after purge = %d, want 0", n)
	}
	if _, err := q.ReadPending(ctx, recipientA, 10); !errors.Is(err, ErrQueueEmpty) {
		t.Fatalf("ReadPending() after purge = %v, want ErrQueueEmpty", err)
	}
}

func TestQueueAckPartialKeepsStream(t *testing.T) {
	q, _ := newTestQueue(t)
	ctx := context.Background()

	e1, _ := q.Enqueue(ctx, recipientH, QueuedMessage{MsgID: "m1", SenderHash: "s", Ciphertext: []byte("a")})
	_, _ = q.Enqueue(ctx, recipientH, QueuedMessage{MsgID: "m2", SenderHash: "s", Ciphertext: []byte("b")})
	if err := q.Ack(ctx, recipientH, e1); err != nil {
		t.Fatalf("Ack() error = %v", err)
	}
	msgs, _ := q.ReadPending(ctx, recipientH, 10)
	if len(msgs) != 1 || msgs[0].MsgID != "m2" {
		t.Fatalf("after partial ack: %+v", msgs)
	}
}

// TestQueueTTLExpiration is the Task 4.4 VERIFY for offline-queue TTL
// expiration: entries older than the retention window are purged by
// XTRIM MINID, fresh entries survive. We XADD entries with explicit
// historical IDs (ms-seq) to simulate age without sleeping 30 days.
func TestQueueTTLExpiration(t *testing.T) {
	q, _ := newTestQueue(t)
	ctx := context.Background()

	now := time.Now().UTC()
	old := now.Add(-31 * 24 * time.Hour) // beyond the 30-day TTL
	fresh := now.Add(-time.Hour)

	// XADD with explicit IDs (real Redis allows custom ms IDs; miniredis
	// honors them lexicographically).
	rdb := q.rdb
	key, err := cache.MsgQueueKey(recipientA)
	if err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		id    string
		msgID string
		age   time.Time
	}{
		{formatStreamID(old), "old-1", old},
		{formatStreamID(old.Add(time.Second)), "old-2", old},
		{formatStreamID(fresh), "fresh-1", fresh},
	} {
		if err := rdb.XAdd(ctx, &redis.XAddArgs{
			Stream: key,
			ID:     tc.id,
			Values: map[string]any{"msg_id": tc.msgID, "sender_hash": "s", "ciphertext": "x"},
		}).Err(); err != nil {
			t.Fatalf("XAdd(%s) error = %v", tc.id, err)
		}
	}

	// Trim everything older than the retention window (now - TTL).
	cutoff := now.Add(-testQueueTTL)
	if err := q.TrimOlderThan(ctx, recipientA, cutoff); err != nil {
		t.Fatalf("TrimOlderThan() error = %v", err)
	}

	msgs, err := q.ReadPending(ctx, recipientA, 10)
	if err != nil {
		t.Fatalf("ReadPending() error = %v", err)
	}
	if len(msgs) != 1 || msgs[0].MsgID != "fresh-1" {
		t.Fatalf("after TTL trim: %+v (want only fresh-1)", msgs)
	}
}

func TestQueuePurge(t *testing.T) {
	q, mr := newTestQueue(t)
	ctx := context.Background()

	_, _ = q.Enqueue(ctx, recipientH, QueuedMessage{MsgID: "m1", SenderHash: "s", Ciphertext: []byte("x")})
	if err := q.Purge(ctx, recipientH); err != nil {
		t.Fatalf("Purge() error = %v", err)
	}
	if mr.Exists(cache.NSMsgQueue + ":" + recipientH) {
		t.Fatal("stream still exists after Purge()")
	}
}

func TestQueueIsolationPerRecipient(t *testing.T) {
	q, _ := newTestQueue(t)
	ctx := context.Background()

	_, _ = q.Enqueue(ctx, hashA, QueuedMessage{MsgID: "a1", SenderHash: "s", Ciphertext: []byte("x")})
	if _, err := q.ReadPending(ctx, hashB, 10); !errors.Is(err, ErrQueueEmpty) {
		t.Fatalf("recipient B sees A's queue: %v", err)
	}
}

// TestQueueRejectsPIIShapedRecipient guards the Task 4.6 key-validation
// boundary in the relay: a non-hex (e.g. raw-phone-shaped) recipient hash is
// rejected at the store instead of creating an arbitrary msg_queue: key.
func TestQueueRejectsPIIShapedRecipient(t *testing.T) {
	q, mr := newTestQueue(t)
	ctx := context.Background()

	for _, bad := range []string{"+919876543210", "recipientA", "blind_hash_alice"} {
		if _, err := q.Enqueue(ctx, bad, QueuedMessage{MsgID: "m1", SenderHash: "s", Ciphertext: []byte("x")}); err == nil {
			t.Errorf("Enqueue(%q) should be rejected (PII-shaped key suffix)", bad)
		}
		if _, err := q.Len(ctx, bad); err == nil {
			t.Errorf("Len(%q) should be rejected", bad)
		}
	}
	// No junk keys were created.
	if n := mr.Keys(); len(n) != 0 {
		t.Fatalf("rejected recipients created keys: %v", n)
	}
}

// formatStreamID renders a time as a Redis stream ID (ms-seq).
func formatStreamID(t time.Time) string {
	return strconv.FormatInt(t.UnixMilli(), 10) + "-0"
}
