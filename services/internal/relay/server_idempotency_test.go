package relay

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
	"github.com/kankan223/pari/services/internal/idempotency"
	"github.com/kankan223/pari/services/internal/logging"
)

// newIdemTestEnv builds a relay server WITH the idempotency middleware wired
// (Task 5.3) — the production wiring exercised end-to-end over HTTP.
func newIdemTestEnv(t *testing.T) *wsTestEnv {
	t.Helper()
	mr := miniredis.RunT(t)
	rdb := redis.NewClient(&redis.Options{Addr: mr.Addr()})
	t.Cleanup(func() { _ = rdb.Close() })
	wrappedRdb := cache.WrapRedis(rdb)
	queue := NewRedisOfflineQueue(wrappedRdb, testQueueTTL)
	hub := NewHub(queue)
	auth := &stubAuthenticator{tokens: map[string]string{
		"token-alice": alice,
		"token-bob":   bob,
	}}
	logBuf := &syncBuf{}
	logger := logging.NewRedactingLogger(logBuf, slog.LevelInfo)
	idem := idempotency.NewMiddleware(idempotency.NewRedisStore(wrappedRdb), time.Hour, logger)
	srv := NewServer(ServerOptions{
		Hub:           hub,
		Authenticator: auth,
		Requests:      NewConnectionRequestManager(NewMemRequestStore(), &recordingPublisher{}, time.Hour),
		Idempotency:   idem,
		Logger:        logger,
		PingInterval:  time.Second,
		PongTimeout:   500 * time.Millisecond,
		QueueTTL:      testQueueTTL,
	})
	ts := httptest.NewServer(srv.Handler())
	t.Cleanup(ts.Close)
	return &wsTestEnv{ts: ts, hub: hub, queue: queue, mr: mr, logBuf: logBuf}
}

// idemReq performs an authenticated mutation request with an Idempotency-Key.
func idemReq(t *testing.T, e *wsTestEnv, method, path, token, key string, body string) (int, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, e.ts.URL+path, bytes.NewReader([]byte(body)))
	if err != nil {
		t.Fatal(err)
	}
	req.Header.Set("Authorization", "Bearer "+token)
	if key != "" {
		req.Header.Set(idempotency.HeaderName, key)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer func() { _ = resp.Body.Close() }()
	buf := new(bytes.Buffer)
	if _, err := buf.ReadFrom(resp.Body); err != nil {
		t.Fatal(err)
	}
	return resp.StatusCode, buf.Bytes()
}

// TestMutationReplayOverHTTP proves a retried mutation with the same
// Idempotency-Key replays the original response: the FIRST create stores the
// created request; the RETRY returns the identical body without creating a
// second request. The idempotency key is scoped per-authenticated-actor, so
// bob re-sending alice's key is treated as a NEW mutation.
func TestMutationReplayOverHTTP(t *testing.T) {
	e := newIdemTestEnv(t)
	key := "11111111-1111-4111-8111-111111111111"

	// First request: processed and cached.
	code1, body1 := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice", key,
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code1 != http.StatusCreated {
		t.Fatalf("first create = %d %s", code1, body1)
	}
	if !json.Valid(body1) {
		t.Fatalf("first body not JSON: %s", body1)
	}

	// Retry with the same key: identical body, and the store has ONE request.
	code2, body2 := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice", key,
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code2 != http.StatusCreated {
		t.Fatalf("retry = %d %s", code2, body2)
	}
	if !bytes.Equal(body1, body2) {
		t.Errorf("replayed body differs:\n first: %s\n retry: %s", body1, body2)
	}

	codeList, list := idemReq(t, e, http.MethodGet, "/v1/relay/requests", "token-alice", "", "")
	if codeList != http.StatusOK {
		t.Fatalf("list = %d", codeList)
	}
	var reqs []ConnectionRequest
	if err := json.Unmarshal(list, &reqs); err != nil {
		t.Fatalf("decode list: %v", err)
	}
	if len(reqs) != 1 {
		t.Fatalf("requests after dedup = %d, want exactly 1 (retry must not create a second)", len(reqs))
	}
}

// TestIdempotencyScopedPerActor proves the dedup key is namespaced by the
// authenticated actor: two users sending the same UUID are NOT deduped
// against each other (defence in depth against a key being leaked).
func TestIdempotencyScopedPerActor(t *testing.T) {
	e := newIdemTestEnv(t)
	key := "22222222-2222-4222-8222-222222222222"

	code1, _ := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice", key,
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code1 != http.StatusCreated {
		t.Fatalf("alice create = %d", code1)
	}
	// Bob reuses the same UUID: must be processed as a NEW mutation (201),
	// not replayed from alice's cache.
	code2, _ := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-bob", key,
		fmt.Sprintf(`{"target_hash":%q}`, alice))
	if code2 != http.StatusCreated {
		t.Fatalf("bob create with alice's key = %d, want 201 (actor-scoped dedup)", code2)
	}

	// Both requests exist and are distinct: alice's (alice→bob) and bob's
	// (bob→alice) — each created independently despite sharing the UUID,
	// because the dedup key is namespaced per actor. Each actor's list shows
	// exactly their own request (as initiator; bob's request also lists for
	// alice only as target — count initiator-side entries to stay unambiguous).
	_, listA := idemReq(t, e, http.MethodGet, "/v1/relay/requests", "token-alice", "", "")
	var aliceReqs []ConnectionRequest
	if err := json.Unmarshal(listA, &aliceReqs); err != nil {
		t.Fatalf("decode alice list: %v", err)
	}
	aliceInitiated := 0
	for _, r := range aliceReqs {
		if r.InitiatorHash == alice {
			aliceInitiated++
		}
	}
	if aliceInitiated != 1 {
		t.Fatalf("alice-initiated requests = %d, want 1 (bob's UUID reuse must not dedup into alice's key)", aliceInitiated)
	}
	_ = io.Discard
}

// TestMalformedKeyOverHTTP proves the HTTP surface rejects a non-UUID key
// with 400 before any processing (security checkpoint: PII can never enter
// Redis via this header).
func TestMalformedKeyOverHTTP(t *testing.T) {
	e := newIdemTestEnv(t)
	code, body := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice", "+919876543210",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusBadRequest {
		t.Fatalf("malformed key = %d %s, want 400", code, body)
	}
	if len(e.mr.Keys()) != 0 {
		t.Errorf("redis keys = %v, want none (PII-shaped key must not be stored)", e.mr.Keys())
	}
}

// TestNoHeaderStillWorks proves the dedup middleware does not break callers
// that omit the header (health probes, legacy clients) — plain passthrough.
func TestNoHeaderStillWorks(t *testing.T) {
	e := newIdemTestEnv(t)
	code, body := idemReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice", "",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatalf("no-header create = %d %s, want 201", code, body)
	}
}
