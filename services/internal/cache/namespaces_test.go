package cache

import (
	"strings"
	"testing"
	"time"
)

// validHash is a well-formed 64-hex blind_hash_id / SHA-256 digest.
const validHash = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

const validFamilyID = "0123456789abcdef0123456789abcdef"

// --- namespace registry coverage (techstack §7.2) ---

func TestNamespacePrefixesMatchSpec(t *testing.T) {
	// The six namespaces currently in production use must match the spec
	// exactly — changing a prefix invalidates every stored key.
	cases := []struct {
		ns   string
		want string
	}{
		{NSOtp, "otp"},
		{NSOtpAttempts, "otp_attempts"},
		{NSRefresh, "refresh"},
		{NSRevoked, "revoked"},
		{NSRevokedFamily, "revoked_family"},
		{NSMsgQueue, "msg_queue"},
		{NSKarma, "karma"},
		{NSVoteBuffer, "vote_buffer"},
		{NSAnalystLoad, "analyst_load"},
		{NSRate, "rate"},
		{NSIdempotency, "idempotency"},
	}
	for _, c := range cases {
		if c.ns != c.want {
			t.Errorf("namespace constant = %q, want %q", c.ns, c.want)
		}
	}
}

func TestTTLPoliciesMatchSpec(t *testing.T) {
	cases := []struct {
		name string
		got  time.Duration
		want time.Duration
	}{
		{"otp", OtpTTL, 10 * time.Minute},
		{"otp_attempts", OtpAttemptsTTL, 10 * time.Minute},
		{"refresh", RefreshTTL, 30 * 24 * time.Hour},
		{"revoked", RevokedTTL, 30 * 24 * time.Hour},
		{"revoked_family", RevokedFamilyTTL, 30 * 24 * time.Hour},
		{"msg_queue", MsgQueueTTL, 30 * 24 * time.Hour},
		{"karma", KarmaTTL, 5 * time.Minute},
		{"vote_buffer", VoteBufferTTL, 0},
		{"analyst_load", AnalystLoadTTL, 0},
		{"rate", RateTTL, time.Minute},
		{"idempotency", IdempotencyTTL, 24 * time.Hour},
	}
	for _, c := range cases {
		if c.got != c.want {
			t.Errorf("%s TTL = %v, want %v", c.name, c.got, c.want)
		}
	}
}

// --- valid inputs build the exact spec keys ---

func TestKeyBuildersProduceSpecKeys(t *testing.T) {
	if k, err := OtpKey(validHash); err != nil || k != "otp:"+validHash {
		t.Fatalf("OtpKey = %q, %v", k, err)
	}
	if k, err := OtpAttemptsKey(validHash); err != nil || k != "otp_attempts:"+validHash {
		t.Fatalf("OtpAttemptsKey = %q, %v", k, err)
	}
	if k, err := RefreshKey(validHash); err != nil || k != "refresh:"+validHash {
		t.Fatalf("RefreshKey = %q, %v", k, err)
	}
	if k, err := RevokedKey(validHash); err != nil || k != "revoked:"+validHash {
		t.Fatalf("RevokedKey = %q, %v", k, err)
	}
	if k, err := RevokedFamilyKey(validFamilyID); err != nil || k != "revoked_family:"+validFamilyID {
		t.Fatalf("RevokedFamilyKey = %q, %v", k, err)
	}
	if k, err := MsgQueueKey(validHash); err != nil || k != "msg_queue:"+validHash {
		t.Fatalf("MsgQueueKey = %q, %v", k, err)
	}
	if k, err := KarmaKey(validHash); err != nil || k != "karma:"+validHash {
		t.Fatalf("KarmaKey = %q, %v", k, err)
	}
	if k, err := VoteBufferKey("post-123"); err != nil || k != "vote_buffer:post-123" {
		t.Fatalf("VoteBufferKey = %q, %v", k, err)
	}
	if k, err := AnalystLoadKey(validHash); err != nil || k != "analyst_load:"+validHash {
		t.Fatalf("AnalystLoadKey = %q, %v", k, err)
	}
	if k, err := RateKey(validHash, "vote"); err != nil || k != "rate:"+validHash+":vote" {
		t.Fatalf("RateKey = %q, %v", k, err)
	}
	if k, err := IdempotencyKey(validUUID); err != nil || k != "idempotency:"+validUUID {
		t.Fatalf("IdempotencyKey = %q, %v", k, err)
	}
	if k, err := IdempotencyKeyScoped(validHash, validUUID); err != nil || k != "idempotency:"+validHash+":"+validUUID {
		t.Fatalf("IdempotencyKeyScoped = %q, %v", k, err)
	}
}

func TestIdempotencyKeyScopedValidation(t *testing.T) {
	// The actor component must be a 64-hex blind hash (never a phone or
	// free-form string), and the key must be a UUID v4.
	for _, badActor := range []string{"", "+919876543210", "14155552671", "alice", strings.Repeat("A", 64)} {
		if k, err := IdempotencyKeyScoped(badActor, validUUID); err == nil {
			t.Errorf("IdempotencyKeyScoped(%q) = %q, want error", badActor, k)
		}
	}
	if k, err := IdempotencyKeyScoped(validHash, "not-a-uuid"); err == nil {
		t.Errorf("IdempotencyKeyScoped(valid, bad uuid) = %q, want error", k)
	}
}

// --- SECURITY CHECKPOINT (Task 4.6): PII can never become a key ---

// invalidSuffixes are PII-shaped inputs that must be rejected by every
// blind-hash/digest key builder: raw E.164 phones (with and without +),
// local/plaintext phone fragments, e-mails, short ids, and non-hex strings.
var invalidSuffixes = []string{
	"+919876543210",   // E.164 phone
	"919876543210",    // phone without +
	"14155552671",     // US-format phone
	"+1-415-555-2671", // formatted phone
	"user@example.com",
	"recipientA",
	"blind_hash_alice",
	"h",
	"hashid1",
	"abc",
	strings.Repeat("z", 64), // non-hex
	strings.Repeat("A", 64), // uppercase hex (shape must be lowercase)
	strings.Repeat("0", 63), // too short
	"",
}

func TestKeyBuildersRejectPIIShapedSuffixes(t *testing.T) {
	builders := []struct {
		name string
		key  func(s string) (string, error)
	}{
		{"OtpKey", OtpKey},
		{"OtpAttemptsKey", OtpAttemptsKey},
		{"RefreshKey", RefreshKey},
		{"RevokedKey", RevokedKey},
		{"MsgQueueKey", MsgQueueKey},
		{"KarmaKey", KarmaKey},
		{"AnalystLoadKey", AnalystLoadKey},
	}
	for _, tc := range builders {
		for _, suffix := range invalidSuffixes {
			key, err := tc.key(suffix)
			if err == nil {
				t.Errorf("%s(%q) = %q, want error (PII-shaped suffix rejected)", tc.name, suffix, key)
			}
		}
	}
}

func TestFamilyKeyRejectsInvalidIDs(t *testing.T) {
	for _, bad := range []string{"+919876543210", "family", strings.Repeat("f", 64), strings.Repeat("0", 31)} {
		if k, err := RevokedFamilyKey(bad); err == nil {
			t.Errorf("RevokedFamilyKey(%q) = %q, want error", bad, k)
		}
	}
	if k, err := RevokedFamilyKey(validFamilyID); err != nil || k != "revoked_family:"+validFamilyID {
		t.Errorf("RevokedFamilyKey(valid) = %q, %v", k, err)
	}
}

// validUUID is a well-formed UUID v4 (Task 5.2 client shape).
const validUUID = "f47ac10b-58cc-4372-a567-0e02b2c3d479"

func TestIdempotencyKeyValidation(t *testing.T) {
	// Valid UUID v4 shapes build the exact key.
	for _, ok := range []string{
		validUUID,
		"00000000-0000-4000-8000-000000000000",
		"ffffffff-ffff-4fff-bfff-ffffffffffff",
		"a1b2c3d4-e5f6-47a8-9b0c-1d2e3f4a5b6c",
	} {
		if !ValidateIdempotencyKey(ok) {
			t.Errorf("ValidateIdempotencyKey(%q) = false, want true", ok)
		}
		if k, err := IdempotencyKey(ok); err != nil || !strings.HasPrefix(k, "idempotency:") {
			t.Errorf("IdempotencyKey(%q) = %q, %v", ok, k, err)
		}
	}
	// Invalid shapes: PII, wrong version/variant, malformed grouping, etc.
	for _, bad := range []string{
		"", "+919876543210", "14155552671", "user@example.com",
		"not-a-uuid", "1234567890abcdef",
		"f47ac10b58cc4372a5670e02b2c3d479",      // no dashes
		"f47ac10b-58cc-1372-a567-0e02b2c3d479",  // version 1, not 4
		"f47ac10b-58cc-4372-c567-0e02b2c3d479",  // variant c, not 8/9/a/b
		"F47AC10B-58CC-4372-A567-0E02B2C3D479",  // uppercase (client emits lowercase)
		"f47ac10b-58cc-4372-a567-0e02b2c3d47",   // too short
		"f47ac10b-58cc-4372-a567-0e02b2c3d4799", // too long
	} {
		if ValidateIdempotencyKey(bad) {
			t.Errorf("ValidateIdempotencyKey(%q) = true, want false", bad)
		}
		if k, err := IdempotencyKey(bad); err == nil {
			t.Errorf("IdempotencyKey(%q) = %q, want error", bad, k)
		}
	}
}

func TestVoteBufferAndRateValidateShapes(t *testing.T) {
	if _, err := VoteBufferKey(""); err == nil {
		t.Error("VoteBufferKey(\"\") should error")
	}
	if _, err := VoteBufferKey("bad id with spaces!"); err == nil {
		t.Error("VoteBufferKey(spacey) should error")
	}
	if _, err := RateKey(validHash, ""); err == nil {
		t.Error("RateKey(_, empty endpoint) should error")
	}
	if _, err := RateKey(validHash, "UPPER"); err == nil {
		t.Error("RateKey(_, invalid endpoint) should error")
	}
}

// --- validators ---

func TestValidateHelpers(t *testing.T) {
	if !ValidateBlindHashID(validHash) {
		t.Error("ValidateBlindHashID(valid) = false")
	}
	if !ValidateTokenHash(validHash) {
		t.Error("ValidateTokenHash(valid) = false")
	}
	if !ValidateFamilyID(validFamilyID) {
		t.Error("ValidateFamilyID(valid) = false")
	}
	for _, bad := range []string{"", "+919876543210", "not-hex"} {
		if ValidateBlindHashID(bad) {
			t.Errorf("ValidateBlindHashID(%q) = true, want false", bad)
		}
	}
}
