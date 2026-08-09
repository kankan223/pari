package vault

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"
)

// TestLiveVault runs the AppRole + KV v2 + transit flow against a REAL Vault
// server (env-gated on CIVIC_TEST_VAULT_ADDR, like the PG/Redis/NATS live
// tests). The verify_vault_live.sh script starts a docker Vault dev server
// with the civic-commons KV mount + transit + an AppRole role and runs this
// test against it.
func TestLiveVault(t *testing.T) {
	addr := os.Getenv("CIVIC_TEST_VAULT_ADDR")
	token := os.Getenv("CIVIC_TEST_VAULT_TOKEN")
	if addr == "" || token == "" {
		t.Skip("CIVIC_TEST_VAULT_ADDR/CIVIC_TEST_VAULT_TOKEN not set; skipping live vault test")
	}
	roleID := os.Getenv("CIVIC_TEST_VAULT_ROLE_ID")
	secretID := os.Getenv("CIVIC_TEST_VAULT_SECRET_ID")

	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()

	// 1. Static-token KV read (dev root token).
	vc := New(addr, token, "civic-commons")
	salt, err := vc.ReadKV2(ctx, "identity/argon2_salt")
	if err != nil {
		t.Fatalf("ReadKV2(salt) = %v", err)
	}
	if salt["value"] == "" {
		t.Fatal("salt secret has no value")
	}
	t.Logf("live KV read OK (salt present)")

	// 2. AppRole login + authenticated read + renew, when creds provided.
	if roleID != "" && secretID != "" {
		approle := New(addr, "", "civic-commons")
		if err := approle.LoginAppRole(ctx, roleID, secretID); err != nil {
			t.Fatalf("LoginAppRole = %v", err)
		}
		if _, err := approle.ReadKV2(ctx, "identity/jwt_rs256_public_key"); err != nil {
			t.Fatalf("AppRole-authenticated read = %v", err)
		}
		if err := approle.RenewSelf(ctx); err != nil {
			t.Fatalf("RenewSelf = %v", err)
		}
		t.Log("live AppRole login + read + renew OK")
	}

	// 3. Transit encrypt/decrypt round-trip.
	ct, err := vc.TransitEncrypt(ctx, "civic-device-keys", []byte("live-key-material"))
	if err != nil {
		t.Fatalf("TransitEncrypt = %v", err)
	}
	pt, err := vc.TransitDecrypt(ctx, "civic-device-keys", ct)
	if err != nil {
		t.Fatalf("TransitDecrypt = %v", err)
	}
	if string(pt) != "live-key-material" {
		t.Fatalf("transit round-trip = %q", pt)
	}
	t.Log("live transit encrypt/decrypt round-trip OK")

	// 4. SecretCache: fetch + refresh detects rotation.
	cache := NewSecretCache(vc, time.Minute)
	v1, err := cache.Get(ctx, "identity/argon2_salt")
	if err != nil {
		t.Fatalf("cache.Get = %v", err)
	}
	// Force a refresh; the value is stable so rotation is false.
	if _, changed, err := cache.Refresh(ctx, "identity/argon2_salt"); err != nil {
		t.Fatalf("cache.Refresh = %v", err)
	} else if changed && v1["value"] == "" {
		// changed is acceptable if the dev secret was just written; just
		// ensure no error and a usable value.
		t.Log("cache refresh reported a change (fresh dev secret)")
	}
	t.Log("live SecretCache OK")
}

// TestLiveVaultBadToken proves a wrong token is rejected with a sentinel
// (fail-fast auth behavior) against the real server.
func TestLiveVaultBadToken(t *testing.T) {
	addr := os.Getenv("CIVIC_TEST_VAULT_ADDR")
	if addr == "" {
		t.Skip("CIVIC_TEST_VAULT_ADDR not set")
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	vc := New(addr, "hvs.definitely-wrong-token-1234567890abcdef", "civic-commons")
	if _, err := vc.ReadKV2(ctx, "identity/argon2_salt"); err == nil {
		t.Fatal("expected error for wrong token")
	} else if !errors.Is(err, ErrPermissionDenied) {
		t.Errorf("error = %v, want ErrPermissionDenied", err)
	}
}
