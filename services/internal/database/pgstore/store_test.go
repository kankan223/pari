package pgstore

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/kankan223/pari/services/internal/identity"
	"github.com/kankan223/pari/services/internal/relay"
)

func TestUsersLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()
	store := pg.Users()

	hash := "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
	if err := store.Create(ctx, identity.User{BlindHashID: hash, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("Create: %v", err)
	}
	// Duplicate.
	err := store.Create(ctx, identity.User{BlindHashID: hash})
	if !errors.Is(err, identity.ErrUserExists) {
		t.Fatalf("duplicate Create error = %v, want ErrUserExists", err)
	}

	u, err := store.Get(ctx, hash)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if u.BlindHashID != hash {
		t.Errorf("Get.BlindHashID = %q", u.BlindHashID)
	}

	// SetUsername round trip.
	if err := store.SetUsername(ctx, hash, "alice_01"); err != nil {
		t.Fatalf("SetUsername: %v", err)
	}
	u, _ = store.Get(ctx, hash)
	if u.Username != "alice_01" {
		t.Errorf("Username after set = %q, want alice_01", u.Username)
	}

	// Unknown user.
	if _, err := store.Get(ctx, "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"); !errors.Is(err, identity.ErrUserNotFound) {
		t.Errorf("Get unknown error = %v, want ErrUserNotFound", err)
	}
}

func TestUsernamesClaimCooldownLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()
	store := pg.Usernames()

	now := time.Now().UTC()
	cooldown := 30 * 24 * time.Hour
	const name = "cooldown_test"
	const ownerA = "1111111111111111111111111111111111111111111111111111111111111111"
	const ownerB = "2222222222222222222222222222222222222222222222222222222222222222"

	if err := store.Claim(ctx, name, ownerA, now, cooldown); err != nil {
		t.Fatalf("first Claim: %v", err)
	}
	// Same owner → taken.
	if err := store.Claim(ctx, name, ownerA, now, cooldown); !errors.Is(err, identity.ErrUsernameTaken) {
		t.Errorf("same-owner Claim error = %v, want ErrUsernameTaken", err)
	}
	// Other owner while held → taken.
	if err := store.Claim(ctx, name, ownerB, now, cooldown); !errors.Is(err, identity.ErrUsernameTaken) {
		t.Errorf("held Claim error = %v, want ErrUsernameTaken", err)
	}

	// Release starts the cooldown; immediate re-claim is blocked.
	if err := store.Release(ctx, name, ownerA, now); err != nil {
		t.Fatalf("Release: %v", err)
	}
	if err := store.Claim(ctx, name, ownerB, now.Add(time.Hour), cooldown); !errors.Is(err, identity.ErrUsernameCooldown) {
		t.Errorf("cooldown Claim error = %v, want ErrUsernameCooldown", err)
	}
	// Even the previous owner is blocked during the cooldown.
	if err := store.Claim(ctx, name, ownerA, now.Add(24*time.Hour), cooldown); !errors.Is(err, identity.ErrUsernameCooldown) {
		t.Errorf("owner re-claim during cooldown error = %v, want ErrUsernameCooldown", err)
	}
	// After the cooldown, anyone may claim.
	if err := store.Claim(ctx, name, ownerB, now.Add(31*24*time.Hour), cooldown); err != nil {
		t.Errorf("post-cooldown Claim: %v", err)
	}

	// Release by a non-owner → not owned.
	if err := store.Release(ctx, name, ownerA, now.Add(32*24*time.Hour)); !errors.Is(err, identity.ErrUsernameNotOwned) {
		t.Errorf("non-owner Release error = %v, want ErrUsernameNotOwned", err)
	}
}

func TestDevicesLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()
	store := pg.Devices()

	const hash = "3333333333333333333333333333333333333333333333333333333333333333"
	// Device must belong to an existing user (FK).
	if err := pg.Users().Create(ctx, identity.User{BlindHashID: hash, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("Create user: %v", err)
	}

	pubKey := base64URL32()
	if err := store.Register(ctx, hash, identity.Device{DeviceID: "d1", PublicKey: pubKey}); err != nil {
		t.Fatalf("Register: %v", err)
	}
	// Invalid key rejected.
	if err := store.Register(ctx, hash, identity.Device{DeviceID: "d2", PublicKey: "not-a-key"}); !errors.Is(err, identity.ErrDeviceInvalidKey) {
		t.Errorf("invalid key error = %v, want ErrDeviceInvalidKey", err)
	}
	// Idempotent re-registration (same device_id) updates the key.
	otherKey := base64URL32()
	if err := store.Register(ctx, hash, identity.Device{DeviceID: "d1", PublicKey: otherKey}); err != nil {
		t.Fatalf("re-Register: %v", err)
	}

	list, err := store.List(ctx, hash)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(list) != 1 {
		t.Fatalf("List len = %d, want 1", len(list))
	}
	// Encrypted at rest but decrypted on read.
	if list[0].PublicKey != otherKey {
		t.Errorf("List key = %q, want %q (pgcrypto round trip)", list[0].PublicKey, otherKey)
	}

	// Cap: 10 devices per identity.
	for i := 2; i <= 10; i++ {
		if err := store.Register(ctx, hash, identity.Device{DeviceID: fmt.Sprintf("d%d", i), PublicKey: base64URL32()}); err != nil {
			t.Fatalf("Register d%d: %v", i, err)
		}
	}
	if err := store.Register(ctx, hash, identity.Device{DeviceID: "d11", PublicKey: base64URL32()}); !errors.Is(err, identity.ErrDeviceLimit) {
		t.Errorf("cap error = %v, want ErrDeviceLimit", err)
	}

	// Revoke.
	if err := store.Revoke(ctx, hash, "d1"); err != nil {
		t.Fatalf("Revoke: %v", err)
	}
	if err := store.Revoke(ctx, hash, "d1"); !errors.Is(err, identity.ErrDeviceNotFound) {
		t.Errorf("double Revoke error = %v, want ErrDeviceNotFound", err)
	}
}

func TestDeviceEncryptionAtRestLive(t *testing.T) {
	// SECURITY CHECKPOINT (Task 4.5): PII columns are encrypted with pgcrypto.
	// The raw column value must not contain the plaintext key, must be
	// non-trivial bytea, and must refuse decryption with a wrong key.
	requireLive(t)
	ctx := context.Background()

	const hash = "4444444444444444444444444444444444444444444444444444444444444444"
	if err := pg.Users().Create(ctx, identity.User{BlindHashID: hash, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("Create user: %v", err)
	}
	plaintext := base64URL32()
	if err := pg.Devices().Register(ctx, hash, identity.Device{DeviceID: "enc1", PublicKey: plaintext}); err != nil {
		t.Fatalf("Register: %v", err)
	}

	// Raw SELECT of the stored column (superuser — bypasses RLS is irrelevant
	// here; this is the at-rest proof).
	var raw []byte
	if err := adminDB.QueryRowContext(ctx,
		`SELECT public_key_enc FROM devices WHERE blind_hash_id = $1 AND device_id = 'enc1'`,
		hash).Scan(&raw); err != nil {
		t.Fatalf("raw read: %v", err)
	}
	if len(raw) == 0 {
		t.Fatal("stored ciphertext is empty")
	}
	// pgp_sym_encrypt output is armored/der-encoded binary; the plaintext
	// key (32 bytes, base64url ~43 chars) must not appear inside it.
	if strings.Contains(string(raw), plaintext) {
		t.Error("stored value contains the plaintext public key — NOT encrypted at rest")
	}
	// Decrypting with the wrong key must fail (pgcrypto key integrity).
	if _, err := adminDB.ExecContext(ctx,
		`SELECT pgp_sym_decrypt(public_key_enc, 'wrong-key') FROM devices WHERE blind_hash_id = $1`,
		hash); err == nil {
		t.Error("pgp_sym_decrypt with wrong key succeeded — expected failure")
	}
	// Decrypting with the store's key yields the exact plaintext.
	var dec string
	if err := adminDB.QueryRowContext(ctx,
		`SELECT pgp_sym_decrypt(public_key_enc, $2)::text FROM devices WHERE blind_hash_id = $1`,
		hash, testEncKey).Scan(&dec); err != nil {
		t.Fatalf("pgp_sym_decrypt with correct key: %v", err)
	}
	if dec != plaintext {
		t.Errorf("decrypted key = %q, want %q", dec, plaintext)
	}
}

func TestConnectionRequestsLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()
	store := pg.Requests()

	const initiator = "5555555555555555555555555555555555555555555555555555555555555555"
	const target = "6666666666666666666666666666666666666666666666666666666666666666"
	now := time.Now().UTC()

	req := relay.ConnectionRequest{
		ID:            "deadbeefdeadbeefdeadbeefdeadbeef",
		InitiatorHash: initiator,
		TargetHash:    target,
		Status:        relay.RequestPending,
		CreatedAt:     now,
		UpdatedAt:     now,
		ExpiresAt:     now.Add(30 * 24 * time.Hour),
	}
	if err := store.Create(ctx, req); err != nil {
		t.Fatalf("Create: %v", err)
	}
	// Idempotent duplicate (same pending pair) is a no-op.
	if err := store.Create(ctx, req); err != nil {
		t.Errorf("duplicate Create: %v (want idempotent no-op)", err)
	}

	got, err := store.Get(ctx, req.ID)
	if err != nil {
		t.Fatalf("Get: %v", err)
	}
	if got.Status != relay.RequestPending || got.InitiatorHash != initiator {
		t.Errorf("Get = %+v", got)
	}

	// FindPending sees it; a different pair does not.
	if _, ok, err := store.FindPending(ctx, initiator, target); err != nil || !ok {
		t.Errorf("FindPending(initiator,target) = ok:%v err:%v, want true", ok, err)
	}
	if _, ok, err := store.FindPending(ctx, target, initiator); err != nil || ok {
		t.Errorf("FindPending(reversed) = ok:%v err:%v, want false", ok, err)
	}

	// CAS: transition to accepted.
	accepted := req
	accepted.Status = relay.RequestAccepted
	accepted.UpdatedAt = now.Add(time.Minute)
	if err := store.Update(ctx, accepted); err != nil {
		t.Fatalf("Update(accepted): %v", err)
	}
	// A second transition from the stored (now terminal) state is rejected.
	if err := store.Update(ctx, req); !errors.Is(err, relay.ErrRequestState) {
		t.Errorf("Update after terminal error = %v, want ErrRequestState", err)
	}
	// Unknown id.
	if _, err := store.Get(ctx, "00000000000000000000000000000000"); !errors.Is(err, relay.ErrRequestNotFound) {
		t.Errorf("Get unknown error = %v, want ErrRequestNotFound", err)
	}

	// ListFor finds it for both parties; ListPending no longer includes it.
	if list, err := store.ListFor(ctx, initiator); err != nil || len(list) != 1 {
		t.Errorf("ListFor(initiator) = %v err:%v", list, err)
	}
	if list, err := store.ListFor(ctx, target); err != nil || len(list) != 1 {
		t.Errorf("ListFor(target) = %v err:%v", list, err)
	}
	// The accepted request must no longer appear in the pending sweep (other
	// tests may leave their own pending rows — assert on membership, not a
	// globally empty list).
	if list, err := store.ListPending(ctx); err != nil {
		t.Errorf("ListPending: %v", err)
	} else {
		for _, r := range list {
			if r.ID == req.ID {
				t.Errorf("ListPending still contains accepted request %s", req.ID)
			}
		}
	}
}

func TestDeviceCapConcurrentLive(t *testing.T) {
	// The per-identity device cap must hold under concurrent registration
	// (pg_advisory_xact_lock serializes the count-then-insert).
	requireLive(t)
	ctx := context.Background()

	const hash = "9999999999999999999999999999999999999999999999999999999999999999"
	if err := pg.Users().Create(ctx, identity.User{BlindHashID: hash, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("Create user: %v", err)
	}

	const attempts = 16 // > cap of 10
	var wg sync.WaitGroup
	for i := 0; i < attempts; i++ {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_ = pg.Devices().Register(ctx, hash, identity.Device{
				DeviceID:  fmt.Sprintf("race-%d", i),
				PublicKey: base64URL32(),
			})
		}(i)
	}
	wg.Wait()

	list, err := pg.Devices().List(ctx, hash)
	if err != nil {
		t.Fatalf("List: %v", err)
	}
	if len(list) > 10 {
		t.Errorf("device count = %d after %d concurrent registrations, want <= 10 (cap)", len(list), attempts)
	}
}

// base64URL32 returns a valid 32-byte base64url-encoded public key.
func base64URL32() string {
	// 32 raw bytes 0x01..0x20 encoded base64url (no padding).
	b := make([]byte, 32)
	for i := range b {
		b[i] = byte(i + 1)
	}
	return rawBase64URL(b)
}
