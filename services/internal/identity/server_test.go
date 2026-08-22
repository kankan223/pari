package identity

import (
	"bytes"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/kankan223/pari/services/internal/logging"
)

// newTestServer wires an httptest server around a fresh service.
func newTestServer(t *testing.T) (*httptest.Server, *testService) {
	t.Helper()
	ts := newTestService(t)
	srv := NewServer(ts.svc, logging.NewRedactingLogger(ts.logBuf, slog.LevelInfo))
	httpSrv := httptest.NewServer(srv.Handler())
	t.Cleanup(httpSrv.Close)
	return httpSrv, ts
}

// httpDo sends a JSON request, reads + closes the response body, and returns
// the status code (plus the raw body). If [out] is non-nil the body is also
// JSON-decoded into it.
func httpDo(t *testing.T, method, url, token string, body any, out any) (int, []byte) {
	t.Helper()
	var reader *bytes.Reader
	if body != nil {
		payload, err := json.Marshal(body)
		if err != nil {
			t.Fatalf("marshal request: %v", err)
		}
		reader = bytes.NewReader(payload)
	} else {
		reader = bytes.NewReader(nil)
	}
	req, err := http.NewRequest(method, url, reader)
	if err != nil {
		t.Fatalf("build request: %v", err)
	}
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do request: %v", err)
	}
	defer func() { _ = resp.Body.Close() }()
	raw, _ := io.ReadAll(resp.Body)
	if out != nil {
		if err := json.Unmarshal(raw, out); err != nil {
			t.Fatalf("decode response: %v (body %s)", err, raw)
		}
	}
	return resp.StatusCode, raw
}

type authResultJSON struct {
	AccessToken  string `json:"access_token"`
	RefreshToken string `json:"refresh_token"`
}

func TestServerFullFlow(t *testing.T) {
	srv, _ := newTestServer(t)

	// 1. Request OTP → blind_hash_id.
	var req struct {
		Requested   bool   `json:"requested"`
		BlindHashID string `json:"blind_hash_id"`
	}
	status, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/request", "", map[string]string{"phone": testPhone}, &req)
	if status != http.StatusOK || !req.Requested || !ValidBlindHashID(req.BlindHashID) {
		t.Fatalf("otp/request = %d %+v", status, req)
	}

	// 2. Verify OTP → tokens.
	var auth authResultJSON
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/verify", "", map[string]string{
		"blind_hash_id": req.BlindHashID, "otp": "123456",
	}, &auth)
	if status != http.StatusOK || auth.AccessToken == "" || auth.RefreshToken == "" {
		t.Fatalf("otp/verify = %d", status)
	}

	// 3. Authenticated /me.
	var me struct {
		User struct {
			BlindHashID string `json:"blind_hash_id"`
		} `json:"user"`
	}
	status, _ = httpDo(t, http.MethodGet, srv.URL+"/v1/identity/me", auth.AccessToken, nil, &me)
	if status != http.StatusOK || me.User.BlindHashID != req.BlindHashID {
		t.Fatalf("me = %d %+v", status, me)
	}

	// 4. Claim username.
	var claim struct {
		Claimed  bool   `json:"claimed"`
		Username string `json:"username"`
	}
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/username/claim", auth.AccessToken, map[string]string{"username": "alice"}, &claim)
	if status != http.StatusOK || !claim.Claimed {
		t.Fatalf("username/claim = %d %+v", status, claim)
	}

	// 5. Register + list devices.
	var devReg struct {
		Registered bool `json:"registered"`
	}
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/devices", auth.AccessToken, map[string]string{
		"device_id": "dev-1", "public_key": testPubKey(0x42),
	}, &devReg)
	if status != http.StatusCreated || !devReg.Registered {
		t.Fatalf("devices = %d %+v", status, devReg)
	}
	var devList struct {
		Devices []Device `json:"devices"`
	}
	status, _ = httpDo(t, http.MethodGet, srv.URL+"/v1/identity/devices", auth.AccessToken, nil, &devList)
	if status != http.StatusOK || len(devList.Devices) != 1 {
		t.Fatalf("devices list = %d %+v", status, devList)
	}

	// 6. Refresh rotation.
	var rotated authResultJSON
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/token/refresh", "", map[string]string{"refresh_token": auth.RefreshToken}, &rotated)
	if status != http.StatusOK || rotated.RefreshToken == "" || rotated.RefreshToken == auth.RefreshToken {
		t.Fatalf("token/refresh = %d", status)
	}

	// 7. Revoke → the rotated token must fail afterwards.
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/token/revoke", "", map[string]string{"refresh_token": rotated.RefreshToken}, nil)
	if status != http.StatusNoContent {
		t.Fatalf("token/revoke = %d", status)
	}
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/token/refresh", "", map[string]string{"refresh_token": rotated.RefreshToken}, nil)
	if status != http.StatusUnauthorized {
		t.Fatalf("refresh after revoke = %d, want 401", status)
	}
}

func TestServerAuthRequired(t *testing.T) {
	srv, _ := newTestServer(t)

	endpoints := []struct {
		method, path string
		body         any
	}{
		{http.MethodGet, "/v1/identity/me", nil},
		{http.MethodPost, "/v1/identity/username/claim", map[string]string{"username": "alice"}},
		{http.MethodPost, "/v1/identity/devices", map[string]string{"device_id": "d", "public_key": testPubKey(0x01)}},
		{http.MethodGet, "/v1/identity/devices", nil},
	}
	for _, e := range endpoints {
		status, _ := httpDo(t, e.method, srv.URL+e.path, "", e.body, nil)
		if status != http.StatusUnauthorized {
			t.Errorf("%s %s without token = %d, want 401", e.method, e.path, status)
		}
	}

	// Garbage bearer token → 401.
	status, _ := httpDo(t, http.MethodGet, srv.URL+"/v1/identity/me", "not-a-jwt", nil, nil)
	if status != http.StatusUnauthorized {
		t.Errorf("garbage token = %d, want 401", status)
	}
}

func TestServerErrorResponses(t *testing.T) {
	srv, _ := newTestServer(t)

	// Invalid phone → 400.
	status, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/request", "", map[string]string{"phone": "abc"}, nil)
	if status != http.StatusBadRequest {
		t.Errorf("invalid phone = %d, want 400", status)
	}

	// Malformed JSON → 400.
	req, _ := http.NewRequest(http.MethodPost, srv.URL+"/v1/identity/otp/request", strings.NewReader("{bad json"))
	req.Header.Set("Content-Type", "application/json")
	r2, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatalf("do: %v", err)
	}
	_ = r2.Body.Close()
	if r2.StatusCode != http.StatusBadRequest {
		t.Errorf("malformed body = %d, want 400", r2.StatusCode)
	}

	// Unknown refresh token → 401.
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/token/refresh", "", map[string]string{"refresh_token": "nope"}, nil)
	if status != http.StatusUnauthorized {
		t.Errorf("unknown refresh = %d, want 401", status)
	}

	// Wrong OTP → 401.
	var reqOTP struct {
		BlindHashID string `json:"blind_hash_id"`
	}
	httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/request", "", map[string]string{"phone": testPhone}, &reqOTP)
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/verify", "", map[string]string{
		"blind_hash_id": reqOTP.BlindHashID, "otp": "999999",
	}, nil)
	if status != http.StatusUnauthorized {
		t.Errorf("wrong otp = %d, want 401", status)
	}
}

func TestServerResponsesNeverLeakPhone(t *testing.T) {
	srv, ts := newTestServer(t)

	status, raw := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/request", "", map[string]string{"phone": testPhone}, nil)
	if status != http.StatusOK {
		t.Fatalf("otp/request = %d", status)
	}
	if strings.Contains(string(raw), testPhone) {
		t.Fatalf("otp/request response leaked the phone: %s", raw)
	}
	if strings.Contains(ts.logBuf.String(), testPhone) {
		t.Fatalf("server logs leaked the phone: %s", ts.logBuf.String())
	}
}

// ---------------------------------------------------------------------------
// Prekey bundle endpoint tests

// validBundle returns a minimal valid PreKeyBundle for testing.
func validBundle() PreKeyBundle {
	// 32-byte base64url-encoded keys.
	ik := "AQIDBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"  // 32 bytes
	spk := "BAUFBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA" // 32 bytes
	// 64-byte Ed25519 signature
	sig := "AAECAwQFBgcICQoLDA0ODxAREhMUFRYXGBkaGxwdHh8gISIjJCUmJygpKissLS4vMDEyMzQ1Njc4OTo7PD0-Pw"
	return PreKeyBundle{
		IdentityKey:          ik,
		SignedPreKeyID:       1,
		SignedPreKey:         spk,
		SignedPreKeySignature: sig,
		OneTimePreKeys: []OneTimePreKeyEntry{
			{KeyID: 1, PublicKey: "CQUFBAUGBwgJCgsMDQ4PEBESExQVFhcYGRobHB0eHyA"},
		},
	}
}

// loginAndGetToken performs the OTP flow and returns the access token + blind hash.
func loginAndGetToken(t *testing.T, srv *httptest.Server) (string, string) {
	t.Helper()
	var req struct {
		Requested   bool   `json:"requested"`
		BlindHashID string `json:"blind_hash_id"`
	}
	status, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/request",
		"", map[string]string{"phone": testPhone}, &req)
	if status != http.StatusOK {
		t.Fatalf("otp/request = %d", status)
	}
	var auth authResultJSON
	status, _ = httpDo(t, http.MethodPost, srv.URL+"/v1/identity/otp/verify",
		"", map[string]string{"blind_hash_id": req.BlindHashID, "otp": "123456"}, &auth)
	if status != http.StatusOK {
		t.Fatalf("otp/verify = %d", status)
	}
	return auth.AccessToken, req.BlindHashID
}

func TestServerPreKeyPublishAndFetch(t *testing.T) {
	srv, _ := newTestServer(t)
	token, hashID := loginAndGetToken(t, srv)

	// Publish prekey bundle.
	bundle := validBundle()
	pStatus, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/prekeys",
		token, bundle, nil)
	if pStatus != http.StatusOK {
		t.Fatalf("prekeys/publish = %d", pStatus)
	}

	// Fetch the bundle.
	var fetched PreKeyBundle
	fStatus, _ := httpDo(t, http.MethodGet,
		srv.URL+"/v1/identity/prekeys/"+hashID,
		token, nil, &fetched)
	if fStatus != http.StatusOK {
		t.Fatalf("prekeys/fetch = %d", fStatus)
	}
	if fetched.IdentityKey != bundle.IdentityKey {
		t.Fatalf("identity key mismatch: got %q, want %q", fetched.IdentityKey, bundle.IdentityKey)
	}
	if fetched.SignedPreKey != bundle.SignedPreKey {
		t.Fatalf("signed prekey mismatch")
	}
	if len(fetched.OneTimePreKeys) != 1 {
		t.Fatalf("one-time prekeys count: got %d, want 1", len(fetched.OneTimePreKeys))
	}
}

func TestServerPreKeyFetchNotFound(t *testing.T) {
	srv, _ := newTestServer(t)
	token, hashID := loginAndGetToken(t, srv)

	// Fetch non-existent bundle → 404.
	fStatus, _ := httpDo(t, http.MethodGet,
		srv.URL+"/v1/identity/prekeys/"+hashID,
		token, nil, nil)
	if fStatus != http.StatusNotFound {
		t.Fatalf("prekeys/fetch non-existent = %d, want 404", fStatus)
	}
}

func TestServerPreKeyPublishNoAuth(t *testing.T) {
	srv, _ := newTestServer(t)

	// Publish without token → 401.
	pStatus, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/prekeys",
		"", validBundle(), nil)
	if pStatus != http.StatusUnauthorized {
		t.Fatalf("prekeys/publish no auth = %d, want 401", pStatus)
	}
}

func TestServerPreKeyPublishInvalidBundle(t *testing.T) {
	srv, _ := newTestServer(t)
	token, _ := loginAndGetToken(t, srv)

	// Publish invalid bundle (empty identity key) → 400.
	bad := PreKeyBundle{IdentityKey: "", SignedPreKey: "x", SignedPreKeySignature: "y"}
	pStatus, _ := httpDo(t, http.MethodPost, srv.URL+"/v1/identity/prekeys",
		token, bad, nil)
	if pStatus != http.StatusBadRequest {
		t.Fatalf("prekeys/publish invalid = %d, want 400", pStatus)
	}
}
