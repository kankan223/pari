package idempotency

import (
	"context"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
)

func newTestStore(t *testing.T) (Store, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	return NewRedisStore(cache.WrapRedis(rdb)), mr
}

func TestClaimFirstCallerWins(t *testing.T) {
	store, mr := newTestStore(t)
	ctx := context.Background()
	key := "idempotency:11111111-1111-4111-8111-111111111111"

	won, err := store.Claim(ctx, key, time.Hour)
	if err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	if !won {
		t.Fatal("first Claim should win")
	}

	// A concurrent duplicate must lose the claim and observe in_progress.
	won2, err := store.Claim(ctx, key, time.Hour)
	if err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	if won2 {
		t.Fatal("second Claim must not win")
	}
	entry, ok, err := store.Get(ctx, key)
	if err != nil || !ok {
		t.Fatalf("Get() = %+v, %v, %v", entry, ok, err)
	}
	if entry.Status != StatusInProgress {
		t.Errorf("status = %q, want in_progress", entry.Status)
	}

	// Key must exist in Redis with the exact namespaced shape.
	if !mr.Exists(key) {
		t.Fatalf("redis key %q not set", key)
	}
}

func TestCompleteAndReplay(t *testing.T) {
	store, _ := newTestStore(t)
	ctx := context.Background()
	key := "idempotency:22222222-2222-4222-8222-222222222222"

	body := []byte(`{"id":"abc","status":"accepted"}`)
	if err := store.Complete(ctx, key, 200, body, "application/json", time.Hour); err != nil {
		t.Fatalf("Complete() error = %v", err)
	}
	entry, ok, err := store.Get(ctx, key)
	if err != nil || !ok {
		t.Fatalf("Get() = %+v, %v, %v", entry, ok, err)
	}
	if entry.Status != StatusCompleted {
		t.Errorf("status = %q, want completed", entry.Status)
	}
	if entry.StatusCode != 200 {
		t.Errorf("status_code = %d, want 200", entry.StatusCode)
	}
	if string(entry.Body) != string(body) {
		t.Errorf("body = %q, want %q", entry.Body, body)
	}
	if entry.ContentType != "application/json" {
		t.Errorf("content_type = %q, want application/json", entry.ContentType)
	}
}

func TestClearRemovesKey(t *testing.T) {
	store, mr := newTestStore(t)
	ctx := context.Background()
	key := "idempotency:33333333-3333-4333-8333-333333333333"

	if _, err := store.Claim(ctx, key, time.Hour); err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	if err := store.Clear(ctx, key); err != nil {
		t.Fatalf("Clear() error = %v", err)
	}
	if mr.Exists(key) {
		t.Fatal("key should be gone after Clear")
	}
	_, ok, err := store.Get(ctx, key)
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if ok {
		t.Fatal("Get() after Clear should report ok=false")
	}
}

func TestTTLExpiryViaFastForward(t *testing.T) {
	// SECURITY/TTL checkpoint: an expired dedup key must allow reprocessing.
	store, mr := newTestStore(t)
	ctx := context.Background()
	key := "idempotency:44444444-4444-4444-8444-444444444444"

	ttl := time.Hour
	if _, err := store.Claim(ctx, key, ttl); err != nil {
		t.Fatalf("Claim() error = %v", err)
	}

	// Before TTL: key present.
	if !mr.Exists(key) {
		t.Fatal("key should exist before TTL")
	}

	// Fast-forward past the TTL — the key must be evicted.
	mr.FastForward(ttl + time.Minute)
	if mr.Exists(key) {
		t.Fatal("key should be evicted after TTL")
	}
	won, err := store.Claim(ctx, key, ttl)
	if err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	if !won {
		t.Fatal("a fresh claim after TTL expiry must win")
	}
}

func TestGetAbsentKey(t *testing.T) {
	store, _ := newTestStore(t)
	ctx := context.Background()
	_, ok, err := store.Get(ctx, "idempotency:55555555-5555-4555-8555-555555555555")
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if ok {
		t.Fatal("Get() on absent key should report ok=false")
	}
}
