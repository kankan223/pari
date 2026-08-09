package relay

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"strings"
	"testing"
)

// doReq performs an HTTP request against the test server and returns the
// status code plus the raw body.
func doReq(t *testing.T, e *wsTestEnv, method, path, token, body string) (int, []byte) {
	t.Helper()
	req, err := http.NewRequest(method, e.ts.URL+path, bytes.NewReader([]byte(body)))
	if err != nil {
		t.Fatal(err)
	}
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
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

// requestID decodes a single request response and returns its ID.
func requestID(t *testing.T, body []byte) string {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(body, &m); err != nil {
		t.Fatalf("decode request: %v", err)
	}
	id, _ := m["ID"].(string)
	return id
}

func TestHealthz(t *testing.T) {
	e := newWSTestEnv(t)
	code, body := doReq(t, e, http.MethodGet, "/v1/relay/healthz", "", "")
	if code != http.StatusOK || !strings.Contains(string(body), `"ok"`) {
		t.Fatalf("healthz = %d %s", code, body)
	}
}

func TestRequestsRequireAuth(t *testing.T) {
	e := newWSTestEnv(t)

	code, _ := doReq(t, e, http.MethodPost, "/v1/relay/requests", "", fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusUnauthorized {
		t.Fatalf("no token → %d, want 401", code)
	}
	code, _ = doReq(t, e, http.MethodPost, "/v1/relay/requests", "bad-token", fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusUnauthorized {
		t.Fatalf("bad token → %d, want 401", code)
	}
}

func TestRequestLifecycleOverHTTP(t *testing.T) {
	e := newWSTestEnv(t)

	// Alice creates a request for Bob.
	code, body := doReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatalf("create → %d, want 201 (%s)", code, body)
	}
	id := requestID(t, body)
	if id == "" {
		t.Fatalf("no request id in %s", body)
	}

	// Duplicate create while pending is idempotent (same ID).
	code, body2 := doReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatalf("duplicate create → %d, want 201", code)
	}
	if id2 := requestID(t, body2); id2 != id {
		t.Fatalf("duplicate create returned new id %s, want %s", id2, id)
	}

	// Bob lists and sees the request.
	code, list := doReq(t, e, http.MethodGet, "/v1/relay/requests", "token-bob", "")
	if code != http.StatusOK {
		t.Fatalf("list → %d, want 200", code)
	}
	var reqs []map[string]any
	if err := json.Unmarshal(list, &reqs); err != nil {
		t.Fatalf("decode list: %v (%s)", err, list)
	}
	if len(reqs) != 1 || reqs[0]["ID"] != id {
		t.Fatalf("bob's list = %s, want [%s]", list, id)
	}

	// Bob accepts.
	code, accepted := doReq(t, e, http.MethodPost, "/v1/relay/requests/"+id+"/accept", "token-bob", "")
	if code != http.StatusOK || !strings.Contains(string(accepted), "accepted") {
		t.Fatalf("accept → %d %s", code, accepted)
	}

	// Accepting again → 409 (no longer pending).
	code, _ = doReq(t, e, http.MethodPost, "/v1/relay/requests/"+id+"/accept", "token-bob", "")
	if code != http.StatusConflict {
		t.Fatalf("double accept → %d, want 409", code)
	}
}

func TestRequestForbiddenAndNotFound(t *testing.T) {
	e := newWSTestEnv(t)

	code, body := doReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatal("create failed")
	}
	id := requestID(t, body)

	// A stranger cannot accept Bob's request.
	code, _ = doReq(t, e, http.MethodPost, "/v1/relay/requests/"+id+"/accept", "token-carol", "")
	if code != http.StatusForbidden {
		t.Fatalf("stranger accept → %d, want 403", code)
	}

	// Unknown request → 404.
	code, _ = doReq(t, e, http.MethodPost, "/v1/relay/requests/nonexistent/accept", "token-bob", "")
	if code != http.StatusNotFound {
		t.Fatalf("unknown request → %d, want 404", code)
	}
}

func TestRejectAndWithdrawOverHTTP(t *testing.T) {
	e := newWSTestEnv(t)

	code, body := doReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatal("create failed")
	}
	id := requestID(t, body)

	code, respBody := doReq(t, e, http.MethodPost, "/v1/relay/requests/"+id+"/reject", "token-bob", "")
	if code != http.StatusOK || !strings.Contains(string(respBody), "rejected") {
		t.Fatalf("reject → %d %s", code, respBody)
	}

	code, body2 := doReq(t, e, http.MethodPost, "/v1/relay/requests", "token-alice",
		fmt.Sprintf(`{"target_hash":%q}`, bob))
	if code != http.StatusCreated {
		t.Fatal("second create failed")
	}
	id2 := requestID(t, body2)

	code, respBody2 := doReq(t, e, http.MethodPost, "/v1/relay/requests/"+id2+"/withdraw", "token-alice", "")
	if code != http.StatusOK || !strings.Contains(string(respBody2), "withdrawn") {
		t.Fatalf("withdraw → %d %s", code, respBody2)
	}
}
