package idempotency

import (
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
)

// validUUID is a well-formed UUID v4 (shape the client emits, Task 5.2).
const validUUID = "f47ac10b-58cc-4372-a567-0e02b2c3d479"

func newTestMiddleware(t *testing.T, ttl time.Duration) (func(http.HandlerFunc) http.HandlerFunc, *miniredis.Miniredis) {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	m := NewMiddleware(NewRedisStore(cache.WrapRedis(rdb)), ttl, slog.New(slog.NewTextHandler(io.Discard, nil)))
	return m.Wrap, mr
}

// echoHandler returns a fixed JSON body with the given status; it counts
// invocations so tests can prove a handler was NOT called on replay.
func countingHandler(status int, body string, calls *atomic.Int64) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(status)
		_, _ = w.Write([]byte(body))
	}
}

func do(wrapped http.HandlerFunc, key string) (*httptest.ResponseRecorder, int) {
	req := httptest.NewRequest(http.MethodPost, "/mutate", strings.NewReader(`{}`))
	if key != "" {
		req.Header.Set(HeaderName, key)
	}
	rec := httptest.NewRecorder()
	wrapped(rec, req)
	return rec, rec.Code
}

// doNoRec is do() for callers that only need the status code.
func doNoRec(wrapped http.HandlerFunc, key string) int {
	_, code := do(wrapped, key)
	return code
}

// --- header handling --------------------------------------------------------

func TestMissingHeaderPassthrough(t *testing.T) {
	wrap, _ := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	code := doNoRec(wrap(countingHandler(http.StatusCreated, `{"ok":true}`, &calls)), "")
	if code != http.StatusCreated {
		t.Fatalf("status = %d, want 201", code)
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want 1 (passthrough must run the handler)", calls.Load())
	}
}

func TestMalformedKeyRejected(t *testing.T) {
	wrap, _ := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	// PII-shaped and malformed keys must be rejected BEFORE Redis: a raw
	// phone number, a short key, and a non-v4 UUID are all 400s and never
	// reach the handler or the store.
	for _, bad := range []string{"+919876543210", "not-a-uuid", "1234567890", "00000000-0000-3000-8000-000000000000"} {
		rec, code := do(wrap(countingHandler(http.StatusCreated, `{"ok":true}`, &calls)), bad)
		if code != http.StatusBadRequest {
			t.Errorf("key %q → status %d, want 400", bad, code)
		}
		if !strings.Contains(rec.Body.String(), "invalid") {
			t.Errorf("key %q → body %q missing error marker", bad, rec.Body.String())
		}
		_ = rec
	}
	if calls.Load() != 0 {
		t.Fatalf("handler must never run for malformed keys (calls = %d)", calls.Load())
	}
}

// --- dedup lifecycle --------------------------------------------------------

func TestFirstRequestProcessedAndCached(t *testing.T) {
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	_, code := do(wrap(countingHandler(http.StatusCreated, `{"id":"req-1"}`, &calls)), validUUID)
	if code != http.StatusCreated {
		t.Fatalf("status = %d, want 201", code)
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want 1", calls.Load())
	}
	// The completed response must now be cached under the namespaced key.
	key := "idempotency:" + validUUID
	if !mr.Exists(key) {
		t.Fatalf("key %q not cached", key)
	}
	raw, err := mr.Get(key)
	if err != nil {
		t.Fatalf("read cached key: %v", err)
	}
	var e Entry
	if err := json.Unmarshal([]byte(raw), &e); err != nil {
		t.Fatalf("decode cached entry: %v", err)
	}
	if e.Status != StatusCompleted || e.StatusCode != 201 || e.ContentType != "application/json" {
		t.Errorf("cached entry = %+v, want completed/201/json", e)
	}
}

func TestRetryReplaysCachedResponse(t *testing.T) {
	wrap, _ := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	h := countingHandler(http.StatusCreated, `{"id":"req-1","status":"accepted"}`, &calls)

	first, code := do(wrap(h), validUUID)
	if code != http.StatusCreated {
		t.Fatalf("first status = %d, want 201", code)
	}

	// Retry with the same key: the handler must NOT run again, and the
	// cached response is replayed byte-for-byte.
	second, code := do(wrap(h), validUUID)
	if code != http.StatusCreated {
		t.Fatalf("retry status = %d, want 201 (replayed)", code)
	}
	if second.Body.String() != first.Body.String() {
		t.Errorf("replayed body = %q, want %q", second.Body.String(), first.Body.String())
	}
	if second.Header().Get("Content-Type") != "application/json" {
		t.Errorf("replayed content-type = %q, want application/json", second.Header().Get("Content-Type"))
	}
	if second.Header().Get("Idempotent-Replayed") != "true" {
		t.Errorf("replay must set Idempotent-Replayed: true, got %q", second.Header().Get("Idempotent-Replayed"))
	}
	if first.Header().Get("Idempotent-Replayed") != "" {
		t.Errorf("fresh response must NOT set Idempotent-Replayed")
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want 1 (retry must not reprocess)", calls.Load())
	}
}

func TestSilentSuccessCached(t *testing.T) {
	// A handler returning 2xx WITHOUT a body or explicit WriteHeader (net/http
	// treats it as 200) must still be cached for replay — the recorder must
	// default its status to 200 instead of treating the key as failed.
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	h := func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		// no WriteHeader, no Write — implicit 200
	}

	code1 := doNoRec(wrap(h), validUUID)
	if code1 != http.StatusOK {
		t.Fatalf("first status = %d, want 200", code1)
	}
	if !mr.Exists("idempotency:" + validUUID) {
		t.Fatal("silent 200 must be cached for replay")
	}
	code2 := doNoRec(wrap(h), validUUID)
	if code2 != http.StatusOK {
		t.Fatalf("retry status = %d, want 200 (replayed)", code2)
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want 1 (retry must replay the silent 200)", calls.Load())
	}
}

func TestInProgressReturnsConflict(t *testing.T) {
	wrap, _ := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	started := make(chan struct{})
	release := make(chan struct{})
	h := func(w http.ResponseWriter, _ *http.Request) {
		calls.Add(1)
		close(started)
		<-release // hold the "in progress" window open
		w.Header().Set("Content-Type", "application/json")
		w.WriteHeader(http.StatusCreated)
		_, _ = w.Write([]byte(`{"ok":true}`))
	}

	// First request claims the key and blocks inside the handler.
	go func() { _, _ = do(wrap(h), validUUID) }()

	// Wait until the first request is genuinely in progress.
	select {
	case <-started:
	case <-time.After(5 * time.Second):
		t.Fatal("first request never started")
	}

	// A concurrent duplicate with the same key must get 409, not re-process.
	_, code := do(wrap(h), validUUID)
	if code != http.StatusConflict {
		t.Fatalf("duplicate status = %d, want 409", code)
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want 1 (duplicate must not process)", calls.Load())
	}
	close(release)
}

func TestConcurrentRacesSingleWinner(t *testing.T) {
	// Many goroutines retrying the same mutation simultaneously: exactly one
	// wins the claim and processes; every other caller gets 409 (in-progress)
	// or the replayed 201 — never a double-apply.
	wrap, _ := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	h := countingHandler(http.StatusCreated, `{"id":"req-1"}`, &calls)

	const n = 16
	results := make(chan int, n)
	var wg sync.WaitGroup
	for i := 0; i < n; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			rec, code := do(wrap(h), validUUID)
			results <- code
			_ = rec
		}()
	}
	wg.Wait()
	close(results)

	// Every response must be either 201 (the one processed run, or a replay
	// of its cached response) or 409 (in-progress duplicate). The critical
	// invariant: the handler ran exactly ONCE across all 16 goroutines.
	ok201 := 0
	conflicts := 0
	for code := range results {
		switch code {
		case http.StatusCreated:
			ok201++
		case http.StatusConflict:
			conflicts++
		default:
			t.Fatalf("unexpected status %d", code)
		}
	}
	if ok201+conflicts != n {
		t.Fatalf("responses = %d, want %d", ok201+conflicts, n)
	}
	if ok201 < 1 {
		t.Fatal("at least one request must complete with 201")
	}
	if calls.Load() != 1 {
		t.Fatalf("handler calls = %d, want exactly 1 (no double-apply under race)", calls.Load())
	}
}

func TestFailedHandlerClearsKeyForRetry(t *testing.T) {
	// A mutation that errors must NOT be cached as success: the key is
	// cleared so the client's next retry reprocesses.
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64

	fail := countingHandler(http.StatusInternalServerError, `{"error":"boom"}`, &calls)
	_, code := do(wrap(fail), validUUID)
	if code != http.StatusInternalServerError {
		t.Fatalf("status = %d, want 500", code)
	}
	if mr.Exists("idempotency:" + validUUID) {
		t.Fatal("failed mutation must clear its dedup key")
	}

	// Retry succeeds and now caches the success.
	ok := countingHandler(http.StatusCreated, `{"id":"req-1"}`, &calls)
	_, code = do(wrap(ok), validUUID)
	if code != http.StatusCreated {
		t.Fatalf("retry status = %d, want 201", code)
	}
	if !mr.Exists("idempotency:" + validUUID) {
		t.Fatal("successful retry must cache its response")
	}
	if calls.Load() != 2 {
		t.Fatalf("handler calls = %d, want 2 (failure + successful retry)", calls.Load())
	}
}

func TestTTLExpiryReprocesses(t *testing.T) {
	// After the dedup window elapses the key is evicted and a retry is
	// treated as a fresh request (standard TTL semantics).
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	h := countingHandler(http.StatusCreated, `{"id":"req-1"}`, &calls)

	do(wrap(h), validUUID)
	if calls.Load() != 1 {
		t.Fatalf("handler calls after first = %d, want 1", calls.Load())
	}

	mr.FastForward(time.Hour + time.Minute)

	rec, code := do(wrap(h), validUUID)
	if code != http.StatusCreated {
		t.Fatalf("post-TTL status = %d, want 201", code)
	}
	if calls.Load() != 2 {
		t.Fatalf("handler calls after TTL = %d, want 2 (reprocessed after expiry)", calls.Load())
	}
	_ = rec
}

// --- security checkpoint ----------------------------------------------------

func TestActorScopingSeparatesUsers(t *testing.T) {
	// With ScopedBy wired, the dedup key is namespaced per actor: alice's
	// completed mutation must NOT be replayed to bob even if bob sends the
	// exact same UUID (defence in depth against key leakage).
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	m := NewMiddleware(NewRedisStore(cache.WrapRedis(rdb)), time.Hour, slog.New(slog.NewTextHandler(io.Discard, nil))).
		ScopedBy(func(r *http.Request) string { return r.Header.Get("X-Actor") })

	alice := "1111111111111111111111111111111111111111111111111111111111111111"
	bob := "2222222222222222222222222222222222222222222222222222222222222222"
	var calls atomic.Int64
	h := countingHandler(http.StatusCreated, `{"id":"req-1"}`, &calls)
	wrapped := m.Wrap(h)

	scopedDo := func(actor string) (*httptest.ResponseRecorder, int) {
		req := httptest.NewRequest(http.MethodPost, "/mutate", strings.NewReader(`{}`))
		req.Header.Set(HeaderName, validUUID)
		req.Header.Set("X-Actor", actor)
		rec := httptest.NewRecorder()
		wrapped(rec, req)
		return rec, rec.Code
	}

	// Alice processes and caches her response.
	_, code := scopedDo(alice)
	if code != http.StatusCreated {
		t.Fatalf("alice status = %d", code)
	}
	if calls.Load() != 1 {
		t.Fatalf("alice handler calls = %d", calls.Load())
	}

	// Bob sends the SAME uuid: must be processed as a fresh mutation, not
	// replayed from alice's cache.
	rec2, code := scopedDo(bob)
	if code != http.StatusCreated {
		t.Fatalf("bob status = %d, want 201 (fresh, actor-scoped)", code)
	}
	if calls.Load() != 2 {
		t.Fatalf("bob handler calls = %d, want 2 (bob's key is distinct)", calls.Load())
	}
	_ = rec2

	// Both keys exist under their own actor namespace.
	if !mr.Exists("idempotency:" + alice + ":" + validUUID) {
		t.Error("alice's scoped key missing")
	}
	if !mr.Exists("idempotency:" + bob + ":" + validUUID) {
		t.Error("bob's scoped key missing")
	}

	// Alice's retry still replays (no reprocess).
	rec3, code := scopedDo(alice)
	if code != http.StatusCreated {
		t.Fatalf("alice retry = %d", code)
	}
	if calls.Load() != 2 {
		t.Fatalf("alice retry must replay, not reprocess (calls = %d)", calls.Load())
	}
	_ = rec3
}

func TestPIIShapedKeysNeverReachRedis(t *testing.T) {
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	h := countingHandler(http.StatusCreated, `{"ok":true}`, &calls)

	for _, pii := range []string{"+919876543210", "14155552671", "user@example.com", "+1-415-555-2671"} {
		_, code := do(wrap(h), pii)
		if code != http.StatusBadRequest {
			t.Errorf("PII key %q → status %d, want 400", pii, code)
		}
	}
	// Zero keys created, zero handler invocations.
	if keys := mr.Keys(); len(keys) != 0 {
		t.Errorf("redis keys = %v, want none (PII must never be stored)", keys)
	}
	if calls.Load() != 0 {
		t.Errorf("handler calls = %d, want 0 for PII-shaped keys", calls.Load())
	}
}

func TestDefaultTTLApplied(t *testing.T) {
	// NewMiddleware must default a zero TTL to 24h (Task 5.3 spec window) —
	// the stored key then carries a ~24h expiry in Redis.
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	m := NewMiddleware(NewRedisStore(cache.WrapRedis(rdb)), 0, slog.New(slog.NewTextHandler(io.Discard, nil)))
	rec, code := do(m.Wrap(countingHandler(http.StatusOK, `{}`, &atomic.Int64{})), validUUID)
	if code != http.StatusOK {
		t.Fatalf("status = %d", code)
	}
	_ = rec
	ttl := mr.TTL("idempotency:" + validUUID)
	if ttl <= 0 || ttl > 24*time.Hour {
		t.Fatalf("key TTL = %v, want ~24h", ttl)
	}
}

// TestCachedResponseBounded verifies an oversized response is streamed to
// the client in full but never buffered for replay (the dedup key is
// cleared, so a retry reprocesses instead of replaying a truncated body).
func TestCachedResponseBounded(t *testing.T) {
	wrap, mr := newTestMiddleware(t, time.Hour)
	var calls atomic.Int64
	big := strings.Repeat("x", 100<<10) // 100 KiB — over the 64 KiB cap
	rec, code := do(wrap(countingHandler(http.StatusOK, big, &calls)), validUUID)
	if code != http.StatusOK {
		t.Fatalf("status = %d", code)
	}
	if rec.Body.Len() != len(big) {
		t.Fatalf("client got %d bytes, want %d", rec.Body.Len(), len(big))
	}
	// Oversized responses must NOT be cached for replay (the key is cleared
	// so a retry reprocesses rather than replaying a truncated body).
	if mr.Exists("idempotency:" + validUUID) {
		t.Fatal("oversized response must not be cached")
	}
	_ = rec
}
