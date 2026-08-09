// Redis key architecture (techstack §7.2).
//
// Every Redis key in Civic Commons is namespaced by a strict prefix and a
// validated suffix:
//
//	otp:{blind_hash_id}            OTP code (bcrypt-hashed value)        TTL 10m
//	otp_attempts:{blind_hash_id}   failed-attempt counter                 TTL 10m
//	refresh:{sha256(token)}        live refresh token entry              TTL 30d
//	revoked:{sha256(token)}        rotated/revoked token → family id     TTL 30d
//	revoked_family:{family_id}     family-wide revocation marker         TTL 30d
//	msg_queue:{blind_hash_id}      undelivered envelope stream           TTL 30d/message
//	karma:{blind_hash_id}          cached karma score (future)           TTL 5m
//	vote_buffer:{post_id}          vote accumulator (future, flushed to PG) no TTL
//	analyst_load:{blind_hash_id}   active case count (future)            session
//	rate:{blind_hash_id}:{endpoint} rate-limit counter (future)          TTL 1m
//	idempotency:{uuid_v4}           server-side dedup (Task 5.3)          TTL 24h
//
// SECURITY (Task 4.6/5.3 checkpoints): suffixes are validated before a key
// is built. A raw E.164 phone number, a raw OTP code, or any free-form
// string can never become a Redis key — the builders reject anything that is
// not a 64-hex blind hash, a 64-hex SHA-256 digest, a 32-hex family id, or a
// UUID v4 idempotency key.
package cache

import (
	"fmt"
	"regexp"
	"time"
)

// Namespace prefixes (strict key architecture).
const (
	NSOtp           = "otp"
	NSOtpAttempts   = "otp_attempts"
	NSRefresh       = "refresh"
	NSRevoked       = "revoked"
	NSRevokedFamily = "revoked_family"
	NSMsgQueue      = "msg_queue"
	NSKarma         = "karma"
	NSVoteBuffer    = "vote_buffer"
	NSAnalystLoad   = "analyst_load"
	NSRate          = "rate"
	NSIdempotency   = "idempotency"
)

// TTL policy per namespace (spec §7.2).
const (
	OtpTTL           = 10 * time.Minute
	OtpAttemptsTTL   = 10 * time.Minute
	RefreshTTL       = 30 * 24 * time.Hour
	RevokedTTL       = 30 * 24 * time.Hour
	RevokedFamilyTTL = 30 * 24 * time.Hour
	MsgQueueTTL      = 30 * 24 * time.Hour // per-message retention
	KarmaTTL         = 5 * time.Minute
	VoteBufferTTL    = 0 // no TTL — flushed to PostgreSQL every 60s
	AnalystLoadTTL   = 0 // session-scoped, managed by the caller
	RateTTL          = time.Minute
	IdempotencyTTL   = 24 * time.Hour // dedup window for mutation retries (Task 5.3)
)

// Validation shapes. Both blind_hash_ids and SHA-256 token digests are
// 64-lowercase-hex strings (identical shape — one regex serves both).
var (
	hex64Re    = regexp.MustCompile(`^[0-9a-f]{64}$`) // blind_hash_id / SHA-256 digest
	familyIDRe = regexp.MustCompile(`^[0-9a-f]{32}$`) // random 16-byte family id
	postIDRe   = regexp.MustCompile(`^[A-Za-z0-9_-]{1,64}$`)
	endpointRe = regexp.MustCompile(`^[a-z][a-z0-9_]{0,31}$`)
	// uuidV4Re matches the canonical RFC 4122 version-4 shape (lowercase hex,
	// version nibble 4, variant nibble 8/9/a/b). The Flutter client emits
	// exactly this shape (Task 5.2), and a UUID v4 is 122 random bits — it can
	// never carry PII, which keeps the no-plaintext-in-Redis-keys invariant.
	uuidV4Re = regexp.MustCompile(`^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$`)
)

// ValidateBlindHashID reports whether [id] is a well-formed 64-hex blind
// hash (same shape the identity service produces for phone numbers).
func ValidateBlindHashID(id string) bool { return hex64Re.MatchString(id) }

// ValidateTokenHash reports whether [h] is a well-formed 64-hex SHA-256
// digest (refresh tokens are stored by hash, never raw).
func ValidateTokenHash(h string) bool { return hex64Re.MatchString(h) }

// ValidateFamilyID reports whether [id] is a well-formed 32-hex family id.
func ValidateFamilyID(id string) bool { return familyIDRe.MatchString(id) }

// ValidateIdempotencyKey reports whether [k] is a well-formed UUID v4 (the
// only shape the Idempotency-Key header may carry — Task 5.3).
func ValidateIdempotencyKey(k string) bool { return uuidV4Re.MatchString(k) }

// OtpKey builds `otp:{blind_hash_id}`.
func OtpKey(blindHashID string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: otp key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	return NSOtp + ":" + blindHashID, nil
}

// OtpAttemptsKey builds `otp_attempts:{blind_hash_id}`.
func OtpAttemptsKey(blindHashID string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: otp_attempts key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	return NSOtpAttempts + ":" + blindHashID, nil
}

// RefreshKey builds `refresh:{sha256(token)}`.
func RefreshKey(tokenHash string) (string, error) {
	if !ValidateTokenHash(tokenHash) {
		return "", fmt.Errorf("cache: refresh key requires a 64-hex SHA-256 digest, got %q", tokenHash)
	}
	return NSRefresh + ":" + tokenHash, nil
}

// RevokedKey builds `revoked:{sha256(token)}`.
func RevokedKey(tokenHash string) (string, error) {
	if !ValidateTokenHash(tokenHash) {
		return "", fmt.Errorf("cache: revoked key requires a 64-hex SHA-256 digest, got %q", tokenHash)
	}
	return NSRevoked + ":" + tokenHash, nil
}

// RevokedFamilyKey builds `revoked_family:{family_id}`.
func RevokedFamilyKey(familyID string) (string, error) {
	if !ValidateFamilyID(familyID) {
		return "", fmt.Errorf("cache: revoked_family key requires a 32-hex family id, got %q", familyID)
	}
	return NSRevokedFamily + ":" + familyID, nil
}

// IdempotencyKey builds `idempotency:{uuid_v4}` (server-side dedup, Task 5.3).
// The suffix is strictly validated as a UUID v4 — a phone, e-mail, or any
// free-form string can never become a key (security checkpoint: no PII in
// Redis keys).
func IdempotencyKey(uuid string) (string, error) {
	if !ValidateIdempotencyKey(uuid) {
		return "", fmt.Errorf("cache: idempotency key requires a UUID v4, got %q", uuid)
	}
	return NSIdempotency + ":" + uuid, nil
}

// IdempotencyKeyScoped builds `idempotency:{blind_hash_id}:{uuid_v4}` — the
// production key shape used by the relay: the dedup window is namespaced per
// authenticated actor, so one user replaying another user's UUID cannot read
// the cached response of a mutation they never made. Both components are
// validated (64-hex actor + UUID v4) before the key is built.
func IdempotencyKeyScoped(blindHashID, uuid string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: scoped idempotency key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	if !ValidateIdempotencyKey(uuid) {
		return "", fmt.Errorf("cache: scoped idempotency key requires a UUID v4, got %q", uuid)
	}
	return NSIdempotency + ":" + blindHashID + ":" + uuid, nil
}

// MsgQueueKey builds `msg_queue:{blind_hash_id}` (Redis Streams offline
// queue, one stream per recipient).
func MsgQueueKey(blindHashID string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: msg_queue key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	return NSMsgQueue + ":" + blindHashID, nil
}

// KarmaKey builds `karma:{blind_hash_id}` (future Karma service cache).
func KarmaKey(blindHashID string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: karma key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	return NSKarma + ":" + blindHashID, nil
}

// VoteBufferKey builds `vote_buffer:{post_id}` (future Ledger vote buffer).
func VoteBufferKey(postID string) (string, error) {
	if !postIDRe.MatchString(postID) {
		return "", fmt.Errorf("cache: vote_buffer key requires a valid post id, got %q", postID)
	}
	return NSVoteBuffer + ":" + postID, nil
}

// AnalystLoadKey builds `analyst_load:{blind_hash_id}` (future War Room cap).
func AnalystLoadKey(blindHashID string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: analyst_load key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	return NSAnalystLoad + ":" + blindHashID, nil
}

// RateKey builds `rate:{blind_hash_id}:{endpoint}` (future rate limiter).
func RateKey(blindHashID, endpoint string) (string, error) {
	if !ValidateBlindHashID(blindHashID) {
		return "", fmt.Errorf("cache: rate key requires a 64-hex blind_hash_id, got %q", blindHashID)
	}
	if !endpointRe.MatchString(endpoint) {
		return "", fmt.Errorf("cache: rate key requires a valid endpoint, got %q", endpoint)
	}
	return NSRate + ":" + blindHashID + ":" + endpoint, nil
}
