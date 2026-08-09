package vault

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
	"time"
)

// vaultTestServer is a scriptable Vault fake serving the endpoints the
// client uses, asserting the X-Vault-Token header where relevant.
type vaultTestServer struct {
	*httptest.Server
	token        string // expected token on authenticated calls
	approleOK    bool
	renewalCalls atomic.Int64
}

func newVaultTestServer(t *testing.T, token string) *vaultTestServer {
	t.Helper()
	v := &vaultTestServer{token: token}
	v.Server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		// AppRole login is unauthenticated.
		if r.URL.Path == "/v1/auth/approle/login" {
			v.handleAppRoleLogin(w, r)
			return
		}
		if h := r.Header.Get("X-Vault-Token"); h != token {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		switch {
		case r.URL.Path == "/v1/auth/token/lookup-self":
			_, _ = w.Write([]byte(`{"data":{"ttl":600,"renewable":true}}`))
		case r.URL.Path == "/v1/auth/token/renew-self":
			v.renewalCalls.Add(1)
			_, _ = w.Write([]byte(`{"auth":{"client_token":"` + token + `"}}`))
		case strings.HasPrefix(r.URL.Path, "/v1/civic-commons/data/"):
			_, _ = w.Write([]byte(`{"data":{"data":{"value":"salt-value","jwt_key":"` +
				`-----BEGIN RSA PRIVATE KEY-----"}}}`))
		case strings.HasPrefix(r.URL.Path, "/v1/civic-commons/metadata/"):
			_, _ = w.Write([]byte(`{"data":{"version":7,"created_time":"2026-08-04T10:00:00Z"}}`))
		case strings.HasPrefix(r.URL.Path, "/v1/transit/encrypt/"):
			var req struct {
				Plaintext string `json:"plaintext"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			_, _ = w.Write([]byte(`{"data":{"ciphertext":"vault:v1:` + req.Plaintext + `"}}`))
		case strings.HasPrefix(r.URL.Path, "/v1/transit/decrypt/"):
			var req struct {
				Ciphertext string `json:"ciphertext"`
			}
			_ = json.NewDecoder(r.Body).Decode(&req)
			pt := strings.TrimPrefix(req.Ciphertext, "vault:v1:")
			_, _ = w.Write([]byte(`{"data":{"plaintext":"` + pt + `"}}`))
		default:
			w.WriteHeader(http.StatusNotFound)
		}
	}))
	t.Cleanup(v.Close)
	return v
}

func (v *vaultTestServer) handleAppRoleLogin(w http.ResponseWriter, r *http.Request) {
	var req struct {
		RoleID   string `json:"role_id"`
		SecretID string `json:"secret_id"`
	}
	_ = json.NewDecoder(r.Body).Decode(&req)
	if req.RoleID != "role-1" || req.SecretID != "secret-1" {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"errors":["permission denied"]}`))
		return
	}
	if !v.approleOK {
		w.WriteHeader(http.StatusForbidden)
		_, _ = w.Write([]byte(`{"errors":["invalid role or secret id"]}`))
		return
	}
	_, _ = w.Write([]byte(`{"auth":{"client_token":"` + v.token + `","lease_duration":600}}`))
}

func TestLoginAppRoleSuccess(t *testing.T) {
	ts := newVaultTestServer(t, "hvs.approle-token-1234567890abcdef")
	ts.approleOK = true

	c := New(ts.URL, "", "civic-commons")
	if err := c.LoginAppRole(context.Background(), "role-1", "secret-1"); err != nil {
		t.Fatalf("LoginAppRole() error = %v", err)
	}
	// The client now authenticates with the AppRole-issued token.
	got, err := c.ReadKV2(context.Background(), "identity/argon2_salt")
	if err != nil {
		t.Fatalf("ReadKV2 after login error = %v", err)
	}
	if got["value"] != "salt-value" {
		t.Errorf("value = %q, want salt-value", got["value"])
	}
}

func TestLoginAppRoleRejected(t *testing.T) {
	ts := newVaultTestServer(t, "tok")
	ts.approleOK = false

	c := New(ts.URL, "", "civic-commons")
	err := c.LoginAppRole(context.Background(), "role-1", "wrong-secret")
	if err == nil {
		t.Fatal("LoginAppRole() expected error for bad secret_id")
	}
	if !errors.Is(err, ErrPermissionDenied) && !strings.Contains(err.Error(), "login") {
		t.Errorf("LoginAppRole() error = %v, want permission/login error", err)
	}
}

func TestLoginAppRoleMissingCreds(t *testing.T) {
	c := New("http://127.0.0.1:1", "", "civic-commons")
	if err := c.LoginAppRole(context.Background(), "", ""); !errors.Is(err, ErrAuthFailed) {
		t.Fatalf("LoginAppRole() error = %v, want ErrAuthFailed", err)
	}
}

func TestLookupSelfAndRenew(t *testing.T) {
	ts := newVaultTestServer(t, "tok")

	c := New(ts.URL, "tok", "civic-commons")
	info, err := c.LookupSelf(context.Background())
	if err != nil {
		t.Fatalf("LookupSelf() error = %v", err)
	}
	if info.TTL != 600*time.Second || !info.Renewable {
		t.Errorf("LookupSelf() = %+v, want TTL 600s renewable", info)
	}
	if err := c.RenewSelf(context.Background()); err != nil {
		t.Fatalf("RenewSelf() error = %v", err)
	}
	if ts.renewalCalls.Load() != 1 {
		t.Errorf("renew-self called %d times, want 1", ts.renewalCalls.Load())
	}
}

func TestConnectAppRoleAndRenewal(t *testing.T) {
	ts := newVaultTestServer(t, "hvs.approle-token-1234567890abcdef")
	ts.approleOK = true

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	c, err := Connect(ctx, Options{
		Addr:          ts.URL,
		Mount:         "civic-commons",
		RoleID:        "role-1",
		SecretID:      "secret-1",
		RenewInterval: 20 * time.Millisecond,
	})
	if err != nil {
		t.Fatalf("Connect() error = %v", err)
	}
	// The renewal loop should fire at least once before we cancel.
	deadline := time.Now().Add(500 * time.Millisecond)
	for ts.renewalCalls.Load() == 0 && time.Now().Before(deadline) {
		time.Sleep(10 * time.Millisecond)
	}
	if ts.renewalCalls.Load() == 0 {
		t.Fatal("background renewal never fired")
	}
	// Client remains functional.
	if got, err := c.ReadKV2(context.Background(), "identity/argon2_salt"); err != nil || got["value"] != "salt-value" {
		t.Fatalf("ReadKV2 with renewed client = %v, %v", got, err)
	}
}

func TestConnectRequiresCredentials(t *testing.T) {
	_, err := Connect(context.Background(), Options{Addr: "http://127.0.0.1:1", Mount: "civic-commons"})
	if err == nil {
		t.Fatal("Connect() expected error with no credentials")
	}
}

func TestConnectStaticToken(t *testing.T) {
	ts := newVaultTestServer(t, "static-tok")
	c, err := Connect(context.Background(), Options{Addr: ts.URL, Mount: "civic-commons", Token: "static-tok"})
	if err != nil {
		t.Fatalf("Connect() error = %v", err)
	}
	if got, err := c.ReadKV2(context.Background(), "identity/argon2_salt"); err != nil || got["value"] != "salt-value" {
		t.Fatalf("ReadKV2 with static token = %v, %v", got, err)
	}
}

func TestReadKV2Meta(t *testing.T) {
	ts := newVaultTestServer(t, "tok")
	c := New(ts.URL, "tok", "civic-commons")

	meta, err := c.ReadKV2Meta(context.Background(), "identity/jwt_rs256_private_key")
	if err != nil {
		t.Fatalf("ReadKV2Meta() error = %v", err)
	}
	if meta.Version != 7 {
		t.Errorf("Version = %d, want 7", meta.Version)
	}
	if meta.CreatedTime.IsZero() {
		t.Error("CreatedTime is zero")
	}
}

func TestTransitRoundTrip(t *testing.T) {
	ts := newVaultTestServer(t, "tok")
	c := New(ts.URL, "tok", "civic-commons")

	plaintext := []byte("device-key-bytes")
	ciphertext, err := c.TransitEncrypt(context.Background(), "civic-device-keys", plaintext)
	if err != nil {
		t.Fatalf("TransitEncrypt() error = %v", err)
	}
	if !strings.HasPrefix(ciphertext, "vault:v1:") {
		t.Errorf("ciphertext = %q, want vault:v1: prefix", ciphertext)
	}
	got, err := c.TransitDecrypt(context.Background(), "civic-device-keys", ciphertext)
	if err != nil {
		t.Fatalf("TransitDecrypt() error = %v", err)
	}
	if string(got) != string(plaintext) {
		t.Errorf("round-trip = %q, want %q", got, plaintext)
	}
}

func TestTransitEncryptBase64(t *testing.T) {
	// Vault transit takes base64 plaintext — assert the client encodes it.
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		var req struct {
			Plaintext string `json:"plaintext"`
		}
		_ = json.NewDecoder(r.Body).Decode(&req)
		raw, err := base64.StdEncoding.DecodeString(req.Plaintext)
		if err != nil {
			t.Errorf("plaintext is not valid base64: %v", err)
		}
		if string(raw) != "hello" {
			t.Errorf("plaintext = %q, want hello", raw)
		}
		_, _ = w.Write([]byte(`{"data":{"ciphertext":"vault:v1:ok"}}`))
	}))
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	if _, err := c.TransitEncrypt(context.Background(), "k", []byte("hello")); err != nil {
		t.Fatalf("TransitEncrypt() error = %v", err)
	}
}

// TestSecretCacheTTL proves cached reads are served from memory until the TTL
// expires, then re-fetched (rotation pickup).
func TestSecretCacheTTL(t *testing.T) {
	var reads atomic.Int64
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		n := reads.Add(1)
		_, _ = w.Write([]byte(`{"data":{"data":{"value":"v` + strings.Repeat("1", int(n)) + `"}}}`))
	}))
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	cache := NewSecretCache(c, 50*time.Millisecond)

	v1, err := cache.Get(context.Background(), "identity/argon2_salt")
	if err != nil || v1["value"] == "" {
		t.Fatalf("first Get() = %v, %v", v1, err)
	}
	if reads.Load() != 1 {
		t.Fatalf("reads after first Get = %d, want 1", reads.Load())
	}
	// Served from cache — no new read.
	if _, err := cache.Get(context.Background(), "identity/argon2_salt"); err != nil {
		t.Fatal(err)
	}
	if reads.Load() != 1 {
		t.Errorf("reads after cached Get = %d, want 1 (cached)", reads.Load())
	}
	// After TTL expiry a fresh read happens.
	time.Sleep(80 * time.Millisecond)
	v3, err := cache.Get(context.Background(), "identity/argon2_salt")
	if err != nil {
		t.Fatal(err)
	}
	if reads.Load() != 2 {
		t.Errorf("reads after TTL expiry = %d, want 2", reads.Load())
	}
	if v3["value"] == v1["value"] {
		t.Errorf("expected rotated value, got same %q", v3["value"])
	}
}

// TestSecretCacheRefreshProves rotation detection: Refresh reports the change
// and replaces the cached copy.
func TestSecretCacheRefresh(t *testing.T) {
	var value atomic.Value
	value.Store("salt-v1")
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		v, _ := value.Load().(string)
		_, _ = w.Write([]byte(`{"data":{"data":{"value":"` + v + `"}}}`))
	}))
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	cache := NewSecretCache(c, time.Minute)

	if _, err := cache.Get(context.Background(), "identity/argon2_salt"); err != nil {
		t.Fatal(err)
	}
	// Rotate the secret server-side and force a refresh.
	value.Store("salt-v2")
	got, changed, err := cache.Refresh(context.Background(), "identity/argon2_salt")
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if !changed {
		t.Error("Refresh() reported no change after rotation")
	}
	if got["value"] != "salt-v2" {
		t.Errorf("after refresh value = %q, want salt-v2", got["value"])
	}
	// Idempotent refresh: no change.
	_, changed, err = cache.Refresh(context.Background(), "identity/argon2_salt")
	if err != nil {
		t.Fatal(err)
	}
	if changed {
		t.Error("Refresh() reported change when value is stable")
	}
}

// TestHTTPErrorMapping proves 401/403/404/500 map to sentinel errors.
func TestHTTPErrorMapping(t *testing.T) {
	cases := []struct {
		status int
		want   error
	}{
		{http.StatusNotFound, ErrSecretNotFound},
		{http.StatusForbidden, ErrPermissionDenied},
		{http.StatusUnauthorized, ErrPermissionDenied},
		{http.StatusServiceUnavailable, ErrUnavailable},
		{http.StatusInternalServerError, nil}, // unexpected → generic error
	}
	for _, tc := range cases {
		ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(tc.status)
		}))
		c := New(ts.URL, "tok", "civic-commons")
		_, err := c.ReadKV2(context.Background(), "identity/argon2_salt")
		ts.Close()
		if tc.want != nil && !errors.Is(err, tc.want) {
			t.Errorf("status %d: err = %v, want %v", tc.status, err, tc.want)
		}
		if tc.want == nil && err == nil {
			t.Errorf("status %d: expected generic error", tc.status)
		}
	}
}

func TestWipeBytes(t *testing.T) {
	b := []byte("super-secret-material")
	WipeBytes(b)
	for _, by := range b {
		if by != 0 {
			t.Fatalf("byte %q not wiped", by)
		}
	}
}
