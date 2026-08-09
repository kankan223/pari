package identity

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"errors"
	"strings"
	"testing"
	"time"

	"golang.org/x/crypto/bcrypt"

	"github.com/kankan223/pari/services/internal/cache"
)

func TestRedisOtpStoreSetGetDelete(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	store := NewRedisOtpStore(ts.rdb)

	hash, err := hashOtpCode("123456")
	if err != nil {
		t.Fatalf("hashOtpCode() error = %v", err)
	}
	if err := store.Set(ctx, testOtpHash("a"), hash, time.Minute); err != nil {
		t.Fatalf("Set() error = %v", err)
	}

	got, err := store.Get(ctx, testOtpHash("a"))
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(got), []byte("123456")); err != nil {
		t.Fatalf("stored value is not the bcrypt hash of the code: %v", err)
	}

	// The raw code must not appear anywhere in the store.
	if strings.Contains(ts.mr.Dump(), "123456") {
		t.Fatal("raw OTP code leaked into Redis")
	}

	if _, err := store.Get(ctx, testOtpHash("b")); !errors.Is(err, ErrOtpNotFound) {
		t.Fatalf("Get() missing = %v, want ErrOtpNotFound", err)
	}

	if err := store.Delete(ctx, testOtpHash("a")); err != nil {
		t.Fatalf("Delete() error = %v", err)
	}
	if _, err := store.Get(ctx, testOtpHash("a")); !errors.Is(err, ErrOtpNotFound) {
		t.Fatalf("Get() after delete = %v, want ErrOtpNotFound", err)
	}
}

func TestRedisOtpStoreTTL(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	store := NewRedisOtpStore(ts.rdb)

	hash, _ := hashOtpCode("000000")
	if err := store.Set(ctx, testOtpHash("h"), hash, time.Minute); err != nil {
		t.Fatalf("Set() error = %v", err)
	}
	key, err := cache.OtpKey(testOtpHash("h"))
	if err != nil {
		t.Fatal(err)
	}
	ttl := ts.mr.TTL(key)
	if ttl < 55*time.Second || ttl > time.Minute {
		t.Fatalf("OTP TTL = %v, want ~1m", ttl)
	}
}

func TestRedisOtpStoreAttempts(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	store := NewRedisOtpStore(ts.rdb)

	n, err := store.Attempts(ctx, testOtpHash("h"))
	if err != nil || n != 0 {
		t.Fatalf("Attempts() = %d, %v; want 0, nil", n, err)
	}
	for i := 1; i <= 3; i++ {
		n, err = store.RecordAttempt(ctx, testOtpHash("h"), time.Minute)
		if err != nil || n != i {
			t.Fatalf("RecordAttempt() #%d = %d, %v; want %d", i, n, err, i)
		}
	}
	if err := store.ClearAttempts(ctx, testOtpHash("h")); err != nil {
		t.Fatalf("ClearAttempts() error = %v", err)
	}
	n, _ = store.Attempts(ctx, testOtpHash("h"))
	if n != 0 {
		t.Fatalf("Attempts() after clear = %d, want 0", n)
	}
}

// testOtpHash returns a valid 64-hex blind_hash_id derived from [seed]
// (the OTP store validates key shapes since Task 4.6).
func testOtpHash(seed string) string {
	sum := sha256.Sum256([]byte(seed))
	return hex.EncodeToString(sum[:])
}

func TestRandomCodeGenerator(t *testing.T) {
	g := RandomCodeGenerator{}
	seen := map[string]bool{}
	for i := 0; i < 10; i++ {
		code, err := g.Generate()
		if err != nil {
			t.Fatalf("Generate() error = %v", err)
		}
		if len(code) != otpCodeLength {
			t.Fatalf("code %q length = %d, want %d", code, len(code), otpCodeLength)
		}
		for _, ch := range code {
			if ch < '0' || ch > '9' {
				t.Fatalf("code %q contains non-digit %q", code, ch)
			}
		}
		seen[code] = true
	}
	if len(seen) < 2 {
		t.Fatal("10 generations produced only one code; random source suspect")
	}
}

func TestHashOtpCodeRoundTrip(t *testing.T) {
	hash, err := hashOtpCode("654321")
	if err != nil {
		t.Fatalf("hashOtpCode() error = %v", err)
	}
	if hash == "654321" {
		t.Fatal("hashOtpCode() returned the plaintext")
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte("654321")); err != nil {
		t.Fatalf("compare valid code failed: %v", err)
	}
	if err := bcrypt.CompareHashAndPassword([]byte(hash), []byte("654322")); err == nil {
		t.Fatal("compare wrong code succeeded")
	}
}
