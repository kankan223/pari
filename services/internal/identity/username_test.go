package identity

import (
	"context"
	"errors"
	"testing"
	"time"
)

const cooldown30d = 30 * 24 * time.Hour

func TestValidUsername(t *testing.T) {
	valid := []string{"alice", "alice_01", "a_b_c", "x1234567890123456789012345678"}
	for _, u := range valid {
		if !ValidUsername(u) {
			t.Errorf("ValidUsername(%q) = false, want true", u)
		}
	}
	invalid := []string{
		"", "ab", "Alice", "alice!", "1alice", "_alice", "alice-01",
		"alice with space", "admin", "root", "CIVIC", "01234567890123456789012345678901", // 32 chars
	}
	for _, u := range invalid {
		if ValidUsername(u) {
			t.Errorf("ValidUsername(%q) = true, want false", u)
		}
	}
}

func TestUsernameClaimAndRelease(t *testing.T) {
	store := NewInMemoryUsernameStore()
	ctx := context.Background()
	now := time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC)

	if err := store.Claim(ctx, "alice", "hashA", now, cooldown30d); err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	// Same identity re-claim is an error (already held).
	if err := store.Claim(ctx, "alice", "hashA", now, cooldown30d); !errors.Is(err, ErrUsernameTaken) {
		t.Fatalf("re-claim same owner = %v, want ErrUsernameTaken", err)
	}
	// Different owner while held.
	if err := store.Claim(ctx, "alice", "hashB", now, cooldown30d); !errors.Is(err, ErrUsernameTaken) {
		t.Fatalf("claim held = %v, want ErrUsernameTaken", err)
	}

	if err := store.Release(ctx, "alice", "hashA", now); err != nil {
		t.Fatalf("Release() error = %v", err)
	}
	// Release by non-owner fails.
	if err := store.Release(ctx, "alice", "hashB", now); !errors.Is(err, ErrUsernameNotOwned) {
		t.Fatalf("release non-owner = %v, want ErrUsernameNotOwned", err)
	}
}

func TestUsernameCooldownBlocksReclaim(t *testing.T) {
	store := NewInMemoryUsernameStore()
	ctx := context.Background()
	now := time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC)

	if err := store.Claim(ctx, "alice", "hashA", now, cooldown30d); err != nil {
		t.Fatalf("Claim() error = %v", err)
	}
	if err := store.Release(ctx, "alice", "hashA", now); err != nil {
		t.Fatalf("Release() error = %v", err)
	}

	// Any claimant (even the previous owner) is blocked during cooldown.
	if err := store.Claim(ctx, "alice", "hashA", now.Add(29*24*time.Hour), cooldown30d); !errors.Is(err, ErrUsernameCooldown) {
		t.Fatalf("claim during cooldown = %v, want ErrUsernameCooldown", err)
	}
	if err := store.Claim(ctx, "alice", "hashB", now.Add(29*24*time.Hour), cooldown30d); !errors.Is(err, ErrUsernameCooldown) {
		t.Fatalf("other claimant during cooldown = %v, want ErrUsernameCooldown", err)
	}

	// At exactly 30 days the username becomes available again.
	if err := store.Claim(ctx, "alice", "hashB", now.Add(30*24*time.Hour), cooldown30d); err != nil {
		t.Fatalf("claim at 30d = %v, want success (boundary inclusive)", err)
	}
}

func TestUsernameServiceFlow(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	// Register a user first.
	hashID := mustRequestAndVerifyPhone(t, ts, testPhone)

	// Claim a valid username.
	if err := ts.svc.ClaimUsername(ctx, hashID, "alice"); err != nil {
		t.Fatalf("ClaimUsername() error = %v", err)
	}
	user, _, err := ts.svc.GetUser(ctx, hashID)
	if err != nil {
		t.Fatalf("GetUser() error = %v", err)
	}
	if user.Username != "alice" {
		t.Fatalf("user.Username = %q, want alice", user.Username)
	}

	// Second identity cannot claim it.
	hashID2 := mustRequestAndVerifyPhone(t, ts, "+919876543210")
	if err := ts.svc.ClaimUsername(ctx, hashID2, "alice"); !errors.Is(err, ErrUsernameClaim) {
		t.Fatalf("duplicate claim = %v, want ErrUsernameClaim", err)
	}

	// Release starts the cooldown.
	if err := ts.svc.ReleaseUsername(ctx, hashID); err != nil {
		t.Fatalf("ReleaseUsername() error = %v", err)
	}
	if err := ts.svc.ClaimUsername(ctx, hashID2, "alice"); !errors.Is(err, ErrUsernameClaim) {
		t.Fatalf("claim during cooldown = %v, want ErrUsernameClaim", err)
	}

	// Invalid username is rejected.
	if err := ts.svc.ClaimUsername(ctx, hashID, "Bad Name!"); !errors.Is(err, ErrUsernameClaim) {
		t.Fatalf("invalid username = %v, want ErrUsernameClaim", err)
	}
}

// mustRequestAndVerifyPhone drives a full OTP request+verify and returns the
// blind_hash_id of the registered user for [phone].
func mustRequestAndVerifyPhone(t *testing.T, ts *testService, phone string) string {
	t.Helper()
	ctx := context.Background()
	hashID, err := ts.svc.RequestOtp(ctx, phone)
	if err != nil {
		t.Fatalf("RequestOtp(%s) error = %v", phone, err)
	}
	if _, err := ts.svc.VerifyOtp(ctx, hashID, "123456"); err != nil {
		t.Fatalf("VerifyOtp() error = %v", err)
	}
	return hashID
}
