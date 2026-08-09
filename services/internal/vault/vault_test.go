package vault

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// newTestServer returns an httptest server that serves the KV v2 envelope for
// the given secret data, asserting the request carries the Vault token.
func newTestServer(t *testing.T, token string, secret map[string]any, status int) *httptest.Server {
	t.Helper()
	return httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.Header.Get("X-Vault-Token") != token {
			w.WriteHeader(http.StatusForbidden)
			return
		}
		if !strings.HasPrefix(r.URL.Path, "/v1/civic-commons/data/") {
			w.WriteHeader(http.StatusNotFound)
			return
		}
		w.WriteHeader(status)
		if status == http.StatusOK {
			_, _ = w.Write([]byte(`{"data":{"data":{"` +
				`argon2_salt":"deadbeef","jwt_key":"` + `-----BEGIN RSA PRIVATE KEY-----` + `"}}}`))
		}
	}))
}

func TestReadKV2OK(t *testing.T) {
	ts := newTestServer(t, "s3cr3t", nil, http.StatusOK)
	defer ts.Close()

	c := New(ts.URL, "s3cr3t", "civic-commons")
	got, err := c.ReadKV2(context.Background(), "identity/argon2_salt")
	if err != nil {
		t.Fatalf("ReadKV2() error = %v", err)
	}
	if got["argon2_salt"] != "deadbeef" {
		t.Errorf("argon2_salt = %q, want deadbeef", got["argon2_salt"])
	}
	if !strings.Contains(got["jwt_key"], "BEGIN RSA PRIVATE KEY") {
		t.Errorf("jwt_key not returned")
	}
}

func TestReadKV2NotFound(t *testing.T) {
	ts := newTestServer(t, "tok", nil, http.StatusNotFound)
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	_, err := c.ReadKV2(context.Background(), "identity/missing")
	if !errors.Is(err, ErrSecretNotFound) {
		t.Fatalf("ReadKV2() error = %v, want ErrSecretNotFound", err)
	}
}

func TestReadKV2Forbidden(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusForbidden)
	}))
	defer ts.Close()

	c := New(ts.URL, "wrong", "civic-commons")
	_, err := c.ReadKV2(context.Background(), "identity/argon2_salt")
	if !errors.Is(err, ErrPermissionDenied) {
		t.Fatalf("ReadKV2() error = %v, want ErrPermissionDenied", err)
	}
}

func TestReadKV2NetworkError(t *testing.T) {
	// Server that immediately closes the connection.
	ts := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	addr := ts.URL
	ts.Close()

	c := New(addr, "tok", "civic-commons")
	if _, err := c.ReadKV2(context.Background(), "identity/argon2_salt"); err == nil {
		t.Fatal("ReadKV2() expected error for closed server")
	}
}

func TestReadKV2BadJSON(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{not json`))
	}))
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	if _, err := c.ReadKV2(context.Background(), "identity/argon2_salt"); err == nil {
		t.Fatal("ReadKV2() expected decode error")
	}
}

func TestReadKV2CoercesNonStringValues(t *testing.T) {
	ts := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		_, _ = w.Write([]byte(`{"data":{"data":{"num":42,"flag":true}}}`))
	}))
	defer ts.Close()

	c := New(ts.URL, "tok", "civic-commons")
	got, err := c.ReadKV2(context.Background(), "identity/anything")
	if err != nil {
		t.Fatalf("ReadKV2() error = %v", err)
	}
	if got["num"] != "42" || got["flag"] != "true" {
		t.Errorf("coercion failed: num=%q flag=%q", got["num"], got["flag"])
	}
}
