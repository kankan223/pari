package identity

import (
	"context"
	"errors"
	"net/http"
	"strings"
	"testing"
	"time"
)

// newLookupTestService wires a service with a claimed username ready for
// lookup tests. Returns the service plus the owner's blind_hash_id and the
// claimed username.
func newLookupTestService(t *testing.T) (*Service, string, string) {
	t.Helper()
	ts := newTestService(t)
	svc := ts.svc

	// Register a user + claim a username directly (no OTP round-trip needed).
	owner := strings.Repeat("a", 64)
	if err := svc.users.Create(context.Background(), User{BlindHashID: owner, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := svc.ClaimUsername(context.Background(), owner, "rekha_k"); err != nil {
		t.Fatalf("claim username: %v", err)
	}
	return svc, owner, "rekha_k"
}

func TestLookupUsernameFound(t *testing.T) {
	svc, owner, username := newLookupTestService(t)

	lookup, err := svc.LookupUsername(context.Background(), username)
	if err != nil {
		t.Fatalf("lookup claimed username: %v", err)
	}
	if lookup.Username != username {
		t.Fatalf("username = %q, want %q", lookup.Username, username)
	}
	if lookup.BlindHashID != owner {
		t.Fatalf("blind_hash_id = %q, want %q", lookup.BlindHashID, owner)
	}
}

func TestLookupUsernameUnknownAndInvalid(t *testing.T) {
	svc, _, _ := newLookupTestService(t)

	unknown := "nobody_here_99"
	if _, err := svc.LookupUsername(context.Background(), unknown); !errors.Is(err, ErrUsernameNotFound) {
		t.Fatalf("unknown username err = %v, want ErrUsernameNotFound", err)
	}

	// Invalid formats (uppercase, too short, reserved) never resolve.
	for _, bad := range []string{"ReKha_K", "ab", "admin"} {
		if _, err := svc.LookupUsername(context.Background(), bad); !errors.Is(err, ErrUsernameNotFound) {
			t.Fatalf("invalid username %q err = %v, want ErrUsernameNotFound", bad, err)
		}
	}
}

func TestLookupUsernameReleasedIsUnavailable(t *testing.T) {
	svc, owner, username := newLookupTestService(t)

	// Release puts the username into the 30-day cooldown — it must NOT
	// resolve for anyone (the cooldown window is a privacy boundary).
	if err := svc.ReleaseUsername(context.Background(), owner); err != nil {
		t.Fatalf("release: %v", err)
	}
	if _, err := svc.LookupUsername(context.Background(), username); !errors.Is(err, ErrUsernameNotFound) {
		t.Fatalf("released username err = %v, want ErrUsernameNotFound", err)
	}
}

func TestServerUsernameLookupOverHTTP(t *testing.T) {
	srv, ts := newTestServer(t)
	owner := strings.Repeat("a", 64)
	username := "rekha_k"
	if err := ts.svc.users.Create(context.Background(), User{BlindHashID: owner, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := ts.svc.ClaimUsername(context.Background(), owner, username); err != nil {
		t.Fatalf("claim username: %v", err)
	}

	// Resolve the owner's access token directly (the full OTP flow is covered
	// by TestServerFullFlow; here we only need a valid subject).
	access, err := ts.svc.signer.IssueAccessToken(context.Background(), owner)
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	var lookup UsernameLookup
	status, raw := httpDo(t, http.MethodGet, srv.URL+"/v1/identity/username/"+username, access, nil, &lookup)
	if status != http.StatusOK {
		t.Fatalf("lookup = %d (%s), want 200", status, raw)
	}
	if lookup.Username != username || lookup.BlindHashID != owner {
		t.Fatalf("lookup = %+v, want username=%s hash=%s", lookup, username, owner)
	}

	// Unknown username → 404.
	status, _ = httpDo(t, http.MethodGet, srv.URL+"/v1/identity/username/nobody_here_99", access, nil, nil)
	if status != http.StatusNotFound {
		t.Fatalf("unknown lookup = %d, want 404", status)
	}
}

func TestServerUsernameLookupAuthAndPhoneLeak(t *testing.T) {
	srv, ts := newTestServer(t)
	owner := strings.Repeat("b", 64)
	username := "civic_helper_99"
	if err := ts.svc.users.Create(context.Background(), User{BlindHashID: owner, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("create user: %v", err)
	}
	if err := ts.svc.ClaimUsername(context.Background(), owner, username); err != nil {
		t.Fatalf("claim username: %v", err)
	}

	// No token → 401 (the search surface cannot be scraped anonymously).
	status, _ := httpDo(t, http.MethodGet, srv.URL+"/v1/identity/username/"+username, "", nil, nil)
	if status != http.StatusUnauthorized {
		t.Fatalf("unauthenticated lookup = %d, want 401", status)
	}

	// The lookup response + logs never contain a phone number.
	access, err := ts.svc.signer.IssueAccessToken(context.Background(), owner)
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	status, raw := httpDo(t, http.MethodGet, srv.URL+"/v1/identity/username/"+username, access, nil, nil)
	if status != http.StatusOK {
		t.Fatalf("lookup = %d, want 200", status)
	}
	if strings.Contains(string(raw), testPhone) {
		t.Fatalf("lookup response leaked the phone: %s", raw)
	}
	if strings.Contains(ts.logBuf.String(), testPhone) {
		t.Fatalf("lookup logs leaked the phone: %s", ts.logBuf.String())
	}
}
