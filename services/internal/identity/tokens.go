package identity

import (
	"context"
	"crypto"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
)

// ---------------------------------------------------------------------------
// RS256 JWT (RFC 7519 / RFC 7515) — implemented with the standard library.
//
// Chosen over a JWT library to honor the project's minimal-dependency policy
// (the user directive: standard net/http and stdlib crypto, no official
// SDKs). The implementation is deliberately small and pinned by unit tests:
// alg is locked to RS256 (alg-confusion safe), exp/iss/aud are enforced, and
// signatures are verified with rsa.VerifyPKCS1v15 directly.
// ---------------------------------------------------------------------------

// jwtAlg is the only accepted signing algorithm.
const jwtAlg = "RS256"

// jwtHeader is the unverified JOSE header.
type jwtHeader struct {
	Alg string `json:"alg"`
	Typ string `json:"typ"`
	Kid string `json:"kid,omitempty"`
}

// jwtClaims is the registered + custom claim set.
type jwtClaims struct {
	Sub string `json:"sub"`
	Iss string `json:"iss,omitempty"`
	Aud string `json:"aud,omitempty"`
	Iat int64  `json:"iat"`
	Exp int64  `json:"exp"`
	Jti string `json:"jti,omitempty"`
}

// Claims is the verified access-token payload exposed to callers.
type Claims struct {
	Subject   string
	Issuer    string
	Audience  string
	IssuedAt  time.Time
	ExpiresAt time.Time
}

// JWT sentinel errors.
var (
	ErrTokenMalformed = errors.New("jwt: malformed token")
	ErrTokenAlgorithm = errors.New("jwt: unsupported algorithm")
	ErrTokenSignature = errors.New("jwt: invalid signature")
	ErrTokenExpired   = errors.New("jwt: token expired")
	ErrTokenInvalid   = errors.New("jwt: token claims invalid")
)

func b64url(b []byte) string { return base64.RawURLEncoding.EncodeToString(b) }

func b64urlDecode(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

// JWTSigner issues RS256 access tokens.
type JWTSigner struct {
	priv *rsa.PrivateKey
	kid  string
	iss  string
	aud  string
	ttl  time.Duration
	now  func() time.Time
}

// NewJWTSigner builds a signer. [kid] is emitted in the header so the Kong
// gateway can select the correct per-consumer public key (key_claim_name: kid).
func NewJWTSigner(priv *rsa.PrivateKey, kid, iss, aud string, ttl time.Duration) *JWTSigner {
	return &JWTSigner{priv: priv, kid: kid, iss: iss, aud: aud, ttl: ttl, now: time.Now}
}

// SetClock overrides the time source (tests).
func (s *JWTSigner) SetClock(now func() time.Time) { s.now = now }

// IssueAccessToken creates a signed access token for [subject] (the
// blind_hash_id) valid for the configured 15-minute TTL.
func (s *JWTSigner) IssueAccessToken(_ context.Context, subject string) (string, error) {
	now := s.now().UTC()
	claims := jwtClaims{
		Sub: subject,
		Iss: s.iss,
		Aud: s.aud,
		Iat: now.Unix(),
		Exp: now.Add(s.ttl).Unix(),
		Jti: randomHex(16),
	}
	return signJWT(s.priv, s.kid, claims)
}

// signJWT builds and signs a compact JWS (RS256).
func signJWT(priv *rsa.PrivateKey, kid string, claims jwtClaims) (string, error) {
	header := jwtHeader{Alg: jwtAlg, Typ: "JWT", Kid: kid}
	hb, err := json.Marshal(header)
	if err != nil {
		return "", fmt.Errorf("jwt: encode header: %w", err)
	}
	pb, err := json.Marshal(claims)
	if err != nil {
		return "", fmt.Errorf("jwt: encode claims: %w", err)
	}

	signingInput := b64url(hb) + "." + b64url(pb)
	digest := sha256.Sum256([]byte(signingInput))
	sig, err := rsa.SignPKCS1v15(rand.Reader, priv, crypto.SHA256, digest[:])
	if err != nil {
		return "", fmt.Errorf("jwt: sign: %w", err)
	}
	return signingInput + "." + b64url(sig), nil
}

// JWTVerifier validates RS256 access tokens against a public key.
type JWTVerifier struct {
	pub *rsa.PublicKey
	iss string
	aud string
	now func() time.Time
}

// NewJWTVerifier builds a verifier enforcing [iss] and [aud] (empty means
// "not enforced").
func NewJWTVerifier(pub *rsa.PublicKey, iss, aud string) *JWTVerifier {
	return &JWTVerifier{pub: pub, iss: iss, aud: aud, now: time.Now}
}

// SetClock overrides the time source (tests).
func (v *JWTVerifier) SetClock(now func() time.Time) { v.now = now }

// VerifyAccessToken validates [token] and returns its claims.
func (v *JWTVerifier) VerifyAccessToken(token string) (*Claims, error) {
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		return nil, ErrTokenMalformed
	}

	hb, err := b64urlDecode(parts[0])
	if err != nil {
		return nil, fmt.Errorf("%w: header", ErrTokenMalformed)
	}
	var hdr jwtHeader
	if err := json.Unmarshal(hb, &hdr); err != nil {
		return nil, fmt.Errorf("%w: header", ErrTokenMalformed)
	}
	// Alg-confusion guard: only RS256 is ever accepted (never "none" or HMAC).
	if hdr.Alg != jwtAlg {
		return nil, ErrTokenAlgorithm
	}

	pb, err := b64urlDecode(parts[1])
	if err != nil {
		return nil, fmt.Errorf("%w: payload", ErrTokenMalformed)
	}
	sig, err := b64urlDecode(parts[2])
	if err != nil {
		return nil, fmt.Errorf("%w: signature", ErrTokenMalformed)
	}

	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	if err := rsa.VerifyPKCS1v15(v.pub, crypto.SHA256, digest[:], sig); err != nil {
		return nil, ErrTokenSignature
	}

	var c jwtClaims
	if err := json.Unmarshal(pb, &c); err != nil {
		return nil, fmt.Errorf("%w: claims", ErrTokenMalformed)
	}
	now := v.now().UTC()
	if c.Sub == "" || c.Exp <= 0 {
		// A token must always carry a subject and an expiry (exp==0 would
		// otherwise be accepted as "never expires").
		return nil, ErrTokenInvalid
	}
	if now.Unix() >= c.Exp {
		return nil, ErrTokenExpired
	}
	if v.iss != "" && c.Iss != v.iss {
		return nil, ErrTokenInvalid
	}
	if v.aud != "" && c.Aud != v.aud {
		return nil, ErrTokenInvalid
	}

	return &Claims{
		Subject:   c.Sub,
		Issuer:    c.Iss,
		Audience:  c.Aud,
		IssuedAt:  time.Unix(c.Iat, 0).UTC(),
		ExpiresAt: time.Unix(c.Exp, 0).UTC(),
	}, nil
}

// ParseRSAPrivateKeyPEM loads an RSA private key from a PEM block (PKCS#1 or
// PKCS#8).
func ParseRSAPrivateKeyPEM(pemBytes []byte) (*rsa.PrivateKey, error) {
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, errors.New("jwt: no PEM block in private key")
	}
	if k, err := x509.ParsePKCS1PrivateKey(block.Bytes); err == nil {
		return k, nil
	}
	k, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return nil, fmt.Errorf("jwt: parse private key: %w", err)
	}
	rsaKey, ok := k.(*rsa.PrivateKey)
	if !ok {
		return nil, errors.New("jwt: PEM block is not an RSA private key")
	}
	return rsaKey, nil
}

// ParseRSAPublicKeyPEM loads an RSA public key from a PEM block (PKIX or
// PKCS#1).
func ParseRSAPublicKeyPEM(pemBytes []byte) (*rsa.PublicKey, error) {
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return nil, errors.New("jwt: no PEM block in public key")
	}
	if k, err := x509.ParsePKIXPublicKey(block.Bytes); err == nil {
		if rsaKey, ok := k.(*rsa.PublicKey); ok {
			return rsaKey, nil
		}
		return nil, errors.New("jwt: PEM block is not an RSA public key")
	}
	return x509.ParsePKCS1PublicKey(block.Bytes)
}

// randomHex returns [n] random bytes hex-encoded.
func randomHex(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		// crypto/rand failure is unrecoverable for token security.
		panic("crypto/rand unavailable: " + err.Error())
	}
	return hex.EncodeToString(b)
}

// randomToken returns [n] random bytes base64url-encoded.
func randomToken(n int) string {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		panic("crypto/rand unavailable: " + err.Error())
	}
	return b64url(b)
}

// sha256Hex returns the hex SHA-256 of [b].
func sha256Hex(b []byte) string {
	sum := sha256.Sum256(b)
	return hex.EncodeToString(sum[:])
}

// ---------------------------------------------------------------------------
// Refresh token management (rotation + revocation), Redis-backed.
//
// Key layout (mirrors the techstack §7.2 namespaces):
//   refresh:{sha256(token)}          → refreshEntry JSON, TTL 30d
//   revoked:{sha256(token)}          → family_id, TTL 30d (rotated/revoked)
//   revoked_family:{family_id}       → "1", TTL 30d (reuse detection)
//
// Rotation: each refresh replaces the token with a fresh one in the same
// family and marks the old token revoked. Replaying a rotated token hits the
// revoked set → the whole family is revoked (token-reuse detection).
// ---------------------------------------------------------------------------

// Refresh token policy constants. Redis keys are built by the validated
// cache namespace builders (Task 4.6): refresh/revoked keys carry only
// SHA-256 digests, revoked_family keys carry the 32-hex family id — a raw
// token can never become a Redis key.
const refreshTokenBytes = 32

// refreshEntry is the value stored for a live refresh token.
type refreshEntry struct {
	BlindHashID string `json:"blind_hash_id"`
	FamilyID    string `json:"family_id"`
	ExpiresAt   int64  `json:"expires_at"` // unix seconds
}

// Refresh sentinel errors.
var (
	ErrRefreshNotFound = errors.New("refresh: unknown token")
	ErrRefreshExpired  = errors.New("refresh: token expired")
	ErrRefreshReuse    = errors.New("refresh: token reuse detected")
	ErrRefreshRevoked  = errors.New("refresh: token revoked")
)

// RefreshStore persists refresh tokens and revocation markers.
type RefreshStore interface {
	StoreRefresh(ctx context.Context, tokenHash, entryJSON string, ttl time.Duration) error
	LoadRefresh(ctx context.Context, tokenHash string) (string, error)
	DeleteRefresh(ctx context.Context, tokenHash string) error
	// RevokedFamilyOf returns the family id recorded for a revoked token hash.
	RevokedFamilyOf(ctx context.Context, tokenHash string) (string, bool, error)
	MarkRevoked(ctx context.Context, tokenHash, familyID string, ttl time.Duration) error
	IsFamilyRevoked(ctx context.Context, familyID string) (bool, error)
	RevokeFamily(ctx context.Context, familyID string, ttl time.Duration) error
}

// RedisRefreshStore is the production RefreshStore.
type RedisRefreshStore struct {
	rdb *redis.Client
}

// NewRedisRefreshStore wraps [rdb].
func NewRedisRefreshStore(rdb *redis.Client) *RedisRefreshStore {
	return &RedisRefreshStore{rdb: rdb}
}

// StoreRefresh implements RefreshStore.
func (s *RedisRefreshStore) StoreRefresh(ctx context.Context, tokenHash, entryJSON string, ttl time.Duration) error {
	key, err := cache.RefreshKey(tokenHash)
	if err != nil {
		return err
	}
	return s.rdb.Set(ctx, key, entryJSON, ttl).Err()
}

// LoadRefresh implements RefreshStore.
func (s *RedisRefreshStore) LoadRefresh(ctx context.Context, tokenHash string) (string, error) {
	key, err := cache.RefreshKey(tokenHash)
	if err != nil {
		return "", err
	}
	v, err := s.rdb.Get(ctx, key).Result()
	if errors.Is(err, redis.Nil) {
		return "", ErrRefreshNotFound
	}
	if err != nil {
		return "", fmt.Errorf("refresh: read store: %w", err)
	}
	return v, nil
}

// DeleteRefresh implements RefreshStore.
func (s *RedisRefreshStore) DeleteRefresh(ctx context.Context, tokenHash string) error {
	key, err := cache.RefreshKey(tokenHash)
	if err != nil {
		return err
	}
	return s.rdb.Del(ctx, key).Err()
}

// RevokedFamilyOf implements RefreshStore.
func (s *RedisRefreshStore) RevokedFamilyOf(ctx context.Context, tokenHash string) (string, bool, error) {
	key, err := cache.RevokedKey(tokenHash)
	if err != nil {
		return "", false, err
	}
	v, err := s.rdb.Get(ctx, key).Result()
	if errors.Is(err, redis.Nil) {
		return "", false, nil
	}
	if err != nil {
		return "", false, fmt.Errorf("refresh: read revoked: %w", err)
	}
	return v, true, nil
}

// MarkRevoked implements RefreshStore.
func (s *RedisRefreshStore) MarkRevoked(ctx context.Context, tokenHash, familyID string, ttl time.Duration) error {
	key, err := cache.RevokedKey(tokenHash)
	if err != nil {
		return err
	}
	return s.rdb.Set(ctx, key, familyID, ttl).Err()
}

// IsFamilyRevoked implements RefreshStore.
func (s *RedisRefreshStore) IsFamilyRevoked(ctx context.Context, familyID string) (bool, error) {
	key, err := cache.RevokedFamilyKey(familyID)
	if err != nil {
		return false, err
	}
	n, err := s.rdb.Exists(ctx, key).Result()
	if err != nil {
		return false, fmt.Errorf("refresh: read family: %w", err)
	}
	return n > 0, nil
}

// RevokeFamily implements RefreshStore.
func (s *RedisRefreshStore) RevokeFamily(ctx context.Context, familyID string, ttl time.Duration) error {
	key, err := cache.RevokedFamilyKey(familyID)
	if err != nil {
		return err
	}
	return s.rdb.Set(ctx, key, "1", ttl).Err()
}

// RefreshManager issues, rotates and revokes opaque refresh tokens.
type RefreshManager struct {
	store RefreshStore
	ttl   time.Duration
	now   func() time.Time
}

// NewRefreshManager builds a manager with [ttl] (default 30 days).
func NewRefreshManager(store RefreshStore, ttl time.Duration) *RefreshManager {
	return &RefreshManager{store: store, ttl: ttl, now: time.Now}
}

// SetClock overrides the time source (tests).
func (m *RefreshManager) SetClock(now func() time.Time) { m.now = now }

// Issue creates a new refresh token for [blindHashID] and returns the raw
// token (only the SHA-256 hash is persisted).
func (m *RefreshManager) Issue(ctx context.Context, blindHashID string) (string, error) {
	raw := randomToken(refreshTokenBytes)
	entry, err := json.Marshal(refreshEntry{
		BlindHashID: blindHashID,
		FamilyID:    randomHex(16),
		ExpiresAt:   m.now().UTC().Add(m.ttl).Unix(),
	})
	if err != nil {
		return "", fmt.Errorf("refresh: encode entry: %w", err)
	}
	if err := m.store.StoreRefresh(ctx, sha256Hex([]byte(raw)), string(entry), m.ttl); err != nil {
		return "", fmt.Errorf("refresh: store: %w", err)
	}
	return raw, nil
}

// Refresh rotates [raw] into a new refresh token and returns the new raw
// token plus the owning blind_hash_id.
//
// Security: the old token is deleted and marked revoked; presenting a token
// that was already rotated (or revoked) revokes its whole family.
func (m *RefreshManager) Refresh(ctx context.Context, raw string) (string, string, error) {
	if raw == "" {
		return "", "", ErrRefreshNotFound
	}
	hash := sha256Hex([]byte(raw))

	stored, err := m.store.LoadRefresh(ctx, hash)
	if err != nil {
		if errors.Is(err, ErrRefreshNotFound) {
			// Reuse detection: was it rotated or explicitly revoked?
			family, revoked, rerr := m.store.RevokedFamilyOf(ctx, hash)
			if rerr != nil {
				return "", "", rerr
			}
			if revoked {
				// A replayed (or revoked) token → kill the family.
				if ferr := m.store.RevokeFamily(ctx, family, m.ttl); ferr != nil {
					return "", "", ferr
				}
				return "", "", ErrRefreshReuse
			}
			return "", "", ErrRefreshNotFound
		}
		return "", "", err
	}

	var entry refreshEntry
	if err := json.Unmarshal([]byte(stored), &entry); err != nil {
		return "", "", fmt.Errorf("refresh: corrupt entry: %w", err)
	}
	if m.now().UTC().Unix() >= entry.ExpiresAt {
		_ = m.store.DeleteRefresh(ctx, hash)
		return "", "", ErrRefreshExpired
	}

	revoked, err := m.store.IsFamilyRevoked(ctx, entry.FamilyID)
	if err != nil {
		return "", "", err
	}
	if revoked {
		_ = m.store.DeleteRefresh(ctx, hash)
		return "", "", ErrRefreshRevoked
	}

	// Rotate: new token, same family; old token deleted + marked revoked.
	newRaw := randomToken(refreshTokenBytes)
	newEntry, err := json.Marshal(refreshEntry{
		BlindHashID: entry.BlindHashID,
		FamilyID:    entry.FamilyID,
		ExpiresAt:   m.now().UTC().Add(m.ttl).Unix(),
	})
	if err != nil {
		return "", "", fmt.Errorf("refresh: encode entry: %w", err)
	}
	if err := m.store.StoreRefresh(ctx, sha256Hex([]byte(newRaw)), string(newEntry), m.ttl); err != nil {
		return "", "", fmt.Errorf("refresh: store rotated: %w", err)
	}
	if err := m.store.DeleteRefresh(ctx, hash); err != nil {
		return "", "", fmt.Errorf("refresh: delete old: %w", err)
	}
	if err := m.store.MarkRevoked(ctx, hash, entry.FamilyID, m.ttl); err != nil {
		return "", "", fmt.Errorf("refresh: mark revoked: %w", err)
	}
	return newRaw, entry.BlindHashID, nil
}

// Revoke invalidates [raw] and its entire family (logout / session kill).
// Unknown tokens are treated as idempotent success.
func (m *RefreshManager) Revoke(ctx context.Context, raw string) error {
	if raw == "" {
		return nil
	}
	hash := sha256Hex([]byte(raw))
	stored, err := m.store.LoadRefresh(ctx, hash)
	if err != nil {
		if errors.Is(err, ErrRefreshNotFound) {
			return nil
		}
		return err
	}
	var entry refreshEntry
	if err := json.Unmarshal([]byte(stored), &entry); err != nil {
		return fmt.Errorf("refresh: corrupt entry: %w", err)
	}
	_ = m.store.DeleteRefresh(ctx, hash)
	if err := m.store.MarkRevoked(ctx, hash, entry.FamilyID, m.ttl); err != nil {
		return err
	}
	return m.store.RevokeFamily(ctx, entry.FamilyID, m.ttl)
}
