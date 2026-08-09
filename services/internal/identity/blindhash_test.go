package identity

import (
	"context"
	"testing"
)

// TestHashPhoneClientParity pins the exact vector from the Flutter client
// (Task 2.4 phone_hasher_test.dart), which was cross-checked against the
// argon2-cffi reference implementation with identical parameters
// (memory=65536 KiB, iterations=3, parallelism=4, hash length=32 bytes,
// version 0x13). If this test fails, the server and the client no longer
// agree on blind_hash_id derivation — the whole identity layer breaks.
func TestHashPhoneClientParity(t *testing.T) {
	const (
		phone = "+14155552671"
		salt  = "test_salt_12345"
		want  = "5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2"
	)
	got := DefaultParams().HashPhone(phone, []byte(salt))
	if got != want {
		t.Fatalf("HashPhone() = %s, want %s (client/server parity broken)", got, want)
	}
}

// TestHashPhoneReferenceVectors pins Argon2id outputs verified against the
// reference phc-winner-argon2 CLI (the argon2-specs.pdf KAT generator) with
// the RFC 9106 §5.3 input set — password "password", salt "somesalt". One
// vector covers the lightweight test params (m=32) and one the production
// params (m=65536 = 64 MB).
func TestHashPhoneReferenceVectors(t *testing.T) {
	cases := []struct {
		name string
		p    Params
		want string
	}{
		{
			name: "test-params-m32",
			p:    Params{Memory: 32, Iterations: 3, Parallelism: 4, KeyLength: 32},
			want: "bb0cc80a3e671149526915418c6eefe761bb19d5d2d567a017703e0cea6ab05c",
		},
		{
			name: "production-params-m64MB",
			p:    DefaultParams(),
			want: "661fefbd6f29bcbc8f4646abc32a9d7a4645bb5c059537f8a5587f31adbecccd",
		},
	}
	for _, c := range cases {
		if got := c.p.HashPhone("password", []byte("somesalt")); got != c.want {
			t.Errorf("%s: got %s, want %s", c.name, got, c.want)
		}
	}
}

func TestHashPhoneDeterministic(t *testing.T) {
	p := TestParams()
	a := p.HashPhone(testPhone, []byte("somesalt"))
	b := p.HashPhone(testPhone, []byte("somesalt"))
	if a != b {
		t.Fatalf("HashPhone() not deterministic: %s != %s", a, b)
	}
	if len(a) != 64 {
		t.Fatalf("HashPhone() length = %d, want 64 hex chars", len(a))
	}
}

func TestHashPhoneSaltSensitivity(t *testing.T) {
	p := TestParams()
	a := p.HashPhone(testPhone, []byte("salt-a"))
	b := p.HashPhone(testPhone, []byte("salt-b"))
	if a == b {
		t.Fatal("HashPhone() must differ for different salts")
	}
}

func TestHashPhoneWipesInput(t *testing.T) {
	// The phone byte buffer passed to the hasher must be zeroed afterwards.
	phoneBytes := []byte(testPhone)
	_ = TestParams().hashPhoneBytes(phoneBytes, []byte("salt"))
	for i, b := range phoneBytes {
		if b != 0 {
			t.Fatalf("phone byte %d not wiped (0x%02x)", i, b)
		}
	}
}

func TestStaticSaltProvider(t *testing.T) {
	sp := NewStaticSaltProvider([]byte("deadbeef"))
	got, err := sp.Salt(context.Background())
	if err != nil {
		t.Fatalf("Salt() error = %v", err)
	}
	if string(got) != "deadbeef" {
		t.Fatalf("Salt() = %q, want deadbeef", string(got))
	}
}

func TestValidBlindHashID(t *testing.T) {
	if !ValidBlindHashID("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef") {
		t.Fatal("64-hex id must be valid")
	}
	if ValidBlindHashID("") || ValidBlindHashID("short") ||
		ValidBlindHashID("0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF") ||
		ValidBlindHashID("0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdeg") {
		t.Fatal("invalid ids must be rejected")
	}
}
