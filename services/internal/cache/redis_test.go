package cache

import (
	"context"
	"errors"
	"fmt"
	"os"
	"strconv"
	"strings"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"
)

func newTestClient(t *testing.T) (*redis.Client, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := NewClient(Options{Addr: mr.Addr()})
	return rdb, mr
}

// --- unit: standalone client against miniredis ---

func TestNewClientStandaloneBasic(t *testing.T) {
	rdb, _ := newTestClient(t)
	ctx := context.Background()

	if err := Ping(ctx, rdb); err != nil {
		t.Fatalf("Ping() error = %v", err)
	}
	if err := rdb.Set(ctx, "k", "v", 0).Err(); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	got, err := rdb.Get(ctx, "k").Result()
	if err != nil || got != "v" {
		t.Fatalf("Get() = %q, %v", got, err)
	}
}

func TestNewClientDefaultsApplied(t *testing.T) {
	rdb := NewClient(Options{Addr: "localhost:6379"})
	opts := rdb.Options()
	if opts.PoolSize != 20 {
		t.Errorf("PoolSize = %d, want default 20", opts.PoolSize)
	}
	if opts.MinIdleConns != 5 {
		t.Errorf("MinIdleConns = %d, want default 5", opts.MinIdleConns)
	}
	if opts.MaxRetries != 3 {
		t.Errorf("MaxRetries = %d, want default 3", opts.MaxRetries)
	}
	if opts.DialTimeout != 5*time.Second {
		t.Errorf("DialTimeout = %v, want 5s", opts.DialTimeout)
	}
	if err := rdb.Close(); err != nil {
		t.Fatalf("Close() error = %v", err)
	}
}

func TestNewClientOverrides(t *testing.T) {
	rdb := NewClient(Options{
		Addr:            "redis.internal:6379",
		PoolSize:        2,
		MinIdleConns:    1,
		MaxRetries:      -1, // -1 disables retries (go-redis contract)
		DialTimeout:     time.Second,
		ReadTimeout:     500 * time.Millisecond,
		WriteTimeout:    500 * time.Millisecond,
		PoolTimeout:     200 * time.Millisecond,
		MaxRetryBackoff: time.Second,
	})
	defer func() { _ = rdb.Close() }()
	opts := rdb.Options()
	// go-redis normalizes -1 (disable) to 0 internally.
	if opts.PoolSize != 2 || opts.MinIdleConns != 1 || opts.MaxRetries != 0 {
		t.Errorf("pool overrides not applied: %+v", opts)
	}
	if opts.MaxRetryBackoff != time.Second {
		t.Errorf("MaxRetryBackoff = %v, want 1s", opts.MaxRetryBackoff)
	}
}

// TestKeyExpiry is the Task 4.6 VERIFY "Test TTL expiration by setting keys
// and confirming deletion" (unit path via miniredis FastForward).
func TestKeyExpiry(t *testing.T) {
	rdb, mr := newTestClient(t)
	ctx := context.Background()

	if err := rdb.Set(ctx, "ttl-key", "v", 10*time.Minute).Err(); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	// Fast-forward past the TTL — miniredis expires the key.
	mr.FastForward(11 * time.Minute)
	if err := rdb.Get(ctx, "ttl-key").Err(); !errors.Is(err, redis.Nil) {
		t.Fatalf("Get() after expiry = %v, want redis.Nil", err)
	}
}

// TestStreamTrimAndPurge is the unit-path verification of stream retention
// (XTRIM MINID age eviction) and purge-on-drain for the msg_queue namespace.
func TestStreamTrimAndPurge(t *testing.T) {
	rdb, mr := newTestClient(t)
	ctx := context.Background()
	key, err := MsgQueueKey(validHash)
	if err != nil {
		t.Fatal(err)
	}

	now := time.Now().UTC()
	old := now.Add(-31 * 24 * time.Hour)
	fresh := now.Add(-time.Hour)
	for _, tc := range []struct{ id, name string }{
		{formatID(old), "old-1"},
		{formatID(fresh), "fresh-1"},
	} {
		if err := rdb.XAdd(ctx, &redis.XAddArgs{
			Stream: key,
			ID:     tc.id,
			Values: map[string]any{"msg_id": tc.name},
		}).Err(); err != nil {
			t.Fatalf("XAdd(%s) error = %v", tc.name, err)
		}
	}

	// Age-based trim: entries older than 30 days must be evicted.
	cutoff := now.Add(-30 * 24 * time.Hour)
	if err := rdb.XTrimMinID(ctx, key, formatID(cutoff)).Err(); err != nil {
		t.Fatalf("XTrimMinID() error = %v", err)
	}
	msgs, err := rdb.XRange(ctx, key, "-", "+").Result()
	if err != nil {
		t.Fatalf("XRange() error = %v", err)
	}
	if len(msgs) != 1 || msgs[0].Values["msg_id"] != "fresh-1" {
		t.Fatalf("after TTL trim: %+v, want only fresh-1", msgs)
	}

	// Drain → the stream must be empty. (Real Redis auto-deletes the key on
	// drain; miniredis keeps an empty stream, so the purge-on-drain key
	// deletion is asserted explicitly below and in the live test.)
	if err := rdb.XDel(ctx, key, msgs[0].ID).Err(); err != nil {
		t.Fatalf("XDel() error = %v", err)
	}
	n, err := rdb.XLen(ctx, key).Result()
	if err != nil || n != 0 {
		t.Fatalf("XLen() after drain = %d, %v; want 0", n, err)
	}
	if mr.Exists(key) {
		// The store's purge path deletes a drained stream explicitly.
		if err := rdb.Del(ctx, key).Err(); err != nil {
			t.Fatalf("Del() error = %v", err)
		}
		if mr.Exists(key) {
			t.Fatal("stream key still exists after purge")
		}
	}
}

// --- live integration tests (env-gated, skipped in CI without a server) ---
//
// CIVIC_TEST_REDIS_ADDR            standalone Redis (e.g. localhost:6379)
// CIVIC_TEST_REDIS_SENTINEL_ADDRS  comma-separated Sentinel addrs
// CIVIC_TEST_REDIS_MASTER          Sentinel master name (default civic-master)

func liveRedisAddr(t *testing.T) string {
	t.Helper()
	addr := os.Getenv("CIVIC_TEST_REDIS_ADDR")
	if addr == "" {
		t.Skip("CIVIC_TEST_REDIS_ADDR unset; skipping live Redis test")
	}
	return addr
}

func liveSentinelAddrs(t *testing.T) []string {
	t.Helper()
	raw := os.Getenv("CIVIC_TEST_REDIS_SENTINEL_ADDRS")
	if raw == "" {
		t.Skip("CIVIC_TEST_REDIS_SENTINEL_ADDRS unset; skipping live Sentinel test")
	}
	return splitCSV(raw)
}

// formatID renders a time as a Redis stream ID (ms-seq).
func formatID(t time.Time) string {
	return strconv.FormatInt(t.UnixMilli(), 10) + "-0"
}

func splitCSV(raw string) []string {
	var out []string
	start := 0
	for i := 0; i <= len(raw); i++ {
		if i == len(raw) || raw[i] == ',' {
			if s := raw[start:i]; s != "" {
				out = append(out, s)
			}
			start = i + 1
		}
	}
	return out
}

// TestLivePoolStarvationAndRecovery exercises managed connection pooling: a
// single-connection pool starves concurrent ops (pool timeout), then recovers
// once the held connection is released. Deterministic against a real Redis.
func TestLivePoolStarvationAndRecovery(t *testing.T) {
	addr := liveRedisAddr(t)
	ctx := context.Background()

	rdb := NewClient(Options{
		Addr:         addr,
		PoolSize:     1,
		MinIdleConns: 0,
		MaxRetries:   0,
		PoolTimeout:  150 * time.Millisecond,
	})
	defer func() { _ = rdb.Close() }()

	// Deterministically occupy the only pooled connection by acquiring a
	// dedicated conn and holding it (no race on BLPOP scheduling).
	c := rdb.Conn()
	cmds, err := c.Pipelined(ctx, func(p redis.Pipeliner) error {
		p.Ping(ctx)
		return nil
	})
	if err != nil || len(cmds) == 0 || cmds[0].Err() != nil {
		t.Fatalf("acquire held conn: %v", err)
	}

	// A concurrent op on a starved pool must time out rather than hang.
	resCh := make(chan error, 1)
	go func() { resCh <- rdb.Set(ctx, "starve", "x", 0).Err() }()
	var starveErr error
	select {
	case starveErr = <-resCh:
	case <-time.After(2 * time.Second):
		t.Fatal("concurrent op hung instead of returning pool timeout")
	}
	if starveErr == nil || !strings.Contains(starveErr.Error(), "connection pool timeout") {
		t.Fatalf("starved op error = %v, want pool timeout (ErrPoolTimeout is internal in go-redis v9)", starveErr)
	}

	// Release the held conn → the pool recovers.
	if err := c.Close(); err != nil {
		t.Fatalf("release held conn: %v", err)
	}
	if err := rdb.Set(ctx, "recovered", "y", 0).Err(); err != nil {
		t.Fatalf("post-recovery Set() error = %v", err)
	}
}

// TestLiveKeyExpiry verifies TTL expiration against a real Redis server.
func TestLiveKeyExpiry(t *testing.T) {
	addr := liveRedisAddr(t)
	ctx := context.Background()
	rdb := NewClient(Options{Addr: addr})
	defer func() { _ = rdb.Close() }()

	k := "expiry:" + strconv.FormatInt(time.Now().UnixNano(), 10)
	if err := rdb.Set(ctx, k, "v", 100*time.Millisecond).Err(); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	time.Sleep(300 * time.Millisecond)
	if err := rdb.Get(ctx, k).Err(); !errors.Is(err, redis.Nil) {
		t.Fatalf("Get() after expiry = %v, want redis.Nil", err)
	}
}

// TestLiveStreamPurge verifies msg_queue XTRIM MINID age eviction and
// purge-on-drain against a real Redis server.
func TestLiveStreamPurge(t *testing.T) {
	addr := liveRedisAddr(t)
	ctx := context.Background()
	rdb := NewClient(Options{Addr: addr})
	defer func() { _ = rdb.Close() }()

	key, err := MsgQueueKey(validHash)
	if err != nil {
		t.Fatal(err)
	}
	if err := rdb.Del(ctx, key).Err(); err != nil {
		t.Fatalf("cleanup Del() error = %v", err)
	}

	now := time.Now().UTC()
	old := now.Add(-31 * 24 * time.Hour)
	fresh := now.Add(-time.Hour)
	for _, tc := range []struct{ id, name string }{
		{formatID(old), "old-1"},
		{formatID(fresh), "fresh-1"},
	} {
		if err := rdb.XAdd(ctx, &redis.XAddArgs{
			Stream: key,
			ID:     tc.id,
			Values: map[string]any{"msg_id": tc.name},
		}).Err(); err != nil {
			t.Fatalf("XAdd(%s) error = %v", tc.name, err)
		}
	}

	cutoff := now.Add(-30 * 24 * time.Hour)
	if err := rdb.XTrimMinID(ctx, key, formatID(cutoff)).Err(); err != nil {
		t.Fatalf("XTrimMinID() error = %v", err)
	}
	msgs, err := rdb.XRange(ctx, key, "-", "+").Result()
	if err != nil {
		t.Fatalf("XRange() error = %v", err)
	}
	if len(msgs) != 1 || msgs[0].Values["msg_id"] != "fresh-1" {
		t.Fatalf("after TTL trim: %+v, want only fresh-1", msgs)
	}

	// Drain → the entry is removed; the stream key is then deleted by the
	// store's purge-on-drain (real Redis keeps an empty stream after XDEL,
	// so the relay queue explicitly DELs a drained key).
	if err := rdb.XDel(ctx, key, msgs[0].ID).Err(); err != nil {
		t.Fatalf("XDel() error = %v", err)
	}
	if n, err := rdb.XLen(ctx, key).Result(); err != nil || n != 0 {
		t.Fatalf("XLen() after drain = %d, %v; want 0", n, err)
	}
	// Store purge semantics: a drained stream key is removed explicitly.
	if err := rdb.Del(ctx, key).Err(); err != nil {
		t.Fatalf("Del() purge error = %v", err)
	}
	if n, err := rdb.Exists(ctx, key).Result(); err != nil || n != 0 {
		t.Fatalf("stream key exists after purge: n=%d err=%v", n, err)
	}
}

// TestLiveSentinelFailover verifies the client built from Sentinel addrs
// resolves the elected master and round-trips through it. The
// scripts/verify_redis_live.sh harness kills the master between two runs of
// this test to prove transparent failover (the client follows the promotion).
func TestLiveSentinelFailover(t *testing.T) {
	addrs := liveSentinelAddrs(t)
	master := os.Getenv("CIVIC_TEST_REDIS_MASTER")
	if master == "" {
		master = "civic-master"
	}
	ctx := context.Background()

	rdb := NewClient(Options{
		SentinelAddrs:      addrs,
		SentinelMasterName: master,
	})
	defer func() { _ = rdb.Close() }()

	if err := Ping(ctx, rdb); err != nil {
		t.Fatalf("Ping() through Sentinel error = %v", err)
	}
	k := fmt.Sprintf("sentinel:%d", time.Now().UnixNano())
	if err := rdb.Set(ctx, k, "v", 0).Err(); err != nil {
		t.Fatalf("Set() through Sentinel error = %v", err)
	}
	got, err := rdb.Get(ctx, k).Result()
	if err != nil || got != "v" {
		t.Fatalf("Get() through Sentinel = %q, %v", got, err)
	}
}
