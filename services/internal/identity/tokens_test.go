package identity

import (
	"context"
	"crypto"
	"crypto/hmac"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestJWTIssueVerifyRoundTrip(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	token, err := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	if err != nil {
		t.Fatalf("IssueAccessToken() error = %v", err)
	}
	claims, err := ts.svc.verifier.VerifyAccessToken(token)
	if err != nil {
		t.Fatalf("VerifyAccessToken() error = %v", err)
	}
	if claims.Subject != "hashid123" {
		t.Fatalf("subject = %q, want hashid123", claims.Subject)
	}
	if claims.Issuer != "test-issuer" || claims.Audience != "test-audience" {
		t.Fatalf("iss/aud = %q/%q", claims.Issuer, claims.Audience)
	}
	// 15-minute lifetime.
	if claims.ExpiresAt.Sub(claims.IssuedAt) != 15*time.Minute {
		t.Fatalf("token lifetime = %v, want 15m", claims.ExpiresAt.Sub(claims.IssuedAt))
	}
}

// TestJWTIndependentVerification validates a token produced by our signer
// using the raw RSA primitive + RFC 7515 structure — an independent path that
// proves wire compatibility with any RFC-compliant verifier (e.g. Kong).
func TestJWTIndependentVerification(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	token, err := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	if err != nil {
		t.Fatalf("IssueAccessToken() error = %v", err)
	}
	parts := strings.Split(token, ".")
	if len(parts) != 3 {
		t.Fatalf("token has %d parts, want 3", len(parts))
	}

	// Header must be RS256 / JWT with the configured kid.
	hb, _ := base64.RawURLEncoding.DecodeString(parts[0])
	var hdr jwtHeader
	if err := json.Unmarshal(hb, &hdr); err != nil {
		t.Fatalf("header decode: %v", err)
	}
	if hdr.Alg != "RS256" || hdr.Typ != "JWT" || hdr.Kid != "test-kid" {
		t.Fatalf("header = %+v", hdr)
	}

	// Verify the signature with the raw primitive.
	digest := sha256.Sum256([]byte(parts[0] + "." + parts[1]))
	sig, _ := base64.RawURLEncoding.DecodeString(parts[2])
	if err := rsa.VerifyPKCS1v15(ts.svc.verifier.pub, crypto.SHA256, digest[:], sig); err != nil {
		t.Fatalf("independent RSA verification failed: %v", err)
	}
}

func TestJWTRejectsTamperedPayload(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	token, _ := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	parts := strings.Split(token, ".")
	// Deterministically flip a byte in the payload segment (a naive
	// character swap could accidentally reproduce the original token).
	tampered := parts[0] + "." + flipSegment(parts[1], 4) + "." + parts[2]

	if _, err := ts.svc.verifier.VerifyAccessToken(tampered); !errors.Is(err, ErrTokenSignature) {
		t.Fatalf("tampered token = %v, want ErrTokenSignature", err)
	}
}

func TestJWTRejectsTamperedSignature(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	token, _ := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	parts := strings.Split(token, ".")
	tampered := parts[0] + "." + parts[1] + "." + flipSegment(parts[2], 0)

	if _, err := ts.svc.verifier.VerifyAccessToken(tampered); !errors.Is(err, ErrTokenSignature) {
		t.Fatalf("tampered signature = %v, want ErrTokenSignature", err)
	}
}

func TestJWTRejectsWrongKey(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	token, _ := ts.svc.signer.IssueAccessToken(ctx, "hashid123")

	otherKey, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	otherVerifier := NewJWTVerifier(&otherKey.PublicKey, "test-issuer", "test-audience")
	if _, err := otherVerifier.VerifyAccessToken(token); !errors.Is(err, ErrTokenSignature) {
		t.Fatalf("wrong key = %v, want ErrTokenSignature", err)
	}
}

func TestJWTExpired(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	// Issue, then advance the clock past the 15-minute TTL.
	token, _ := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	ts.svc.SetClock(func() time.Time { return time.Now().Add(16 * time.Minute) })

	if _, err := ts.svc.verifier.VerifyAccessToken(token); !errors.Is(err, ErrTokenExpired) {
		t.Fatalf("expired token = %v, want ErrTokenExpired", err)
	}
}

func TestJWTRejectsAlgConfusion(t *testing.T) {
	ts := newTestService(t)

	// Build a token with alg "none" and an empty signature.
	mk := func(alg string, hmacKey []byte) string {
		h := jwtHeader{Alg: alg, Typ: "JWT"}
		c := jwtClaims{Sub: "hashid123", Exp: time.Now().Add(time.Hour).Unix()}
		hb, _ := json.Marshal(h)
		pb, _ := json.Marshal(c)
		signingInput := base64.RawURLEncoding.EncodeToString(hb) + "." + base64.RawURLEncoding.EncodeToString(pb)
		sig := ""
		if alg == "HS256" {
			mac := hmacSHA256(hmacKey, []byte(signingInput))
			sig = base64.RawURLEncoding.EncodeToString(mac)
		}
		return signingInput + "." + sig
	}

	// "none" attack.
	if _, err := ts.svc.verifier.VerifyAccessToken(mk("none", nil)); !errors.Is(err, ErrTokenAlgorithm) {
		t.Fatalf("alg=none = %v, want ErrTokenAlgorithm", err)
	}
	// HS256 confusion attack (HMAC keyed with the RSA public key bytes).
	pubDER, _ := json.Marshal(ts.svc.verifier.pub)
	if _, err := ts.svc.verifier.VerifyAccessToken(mk("HS256", pubDER)); !errors.Is(err, ErrTokenAlgorithm) {
		t.Fatalf("alg=HS256 = %v, want ErrTokenAlgorithm", err)
	}
}

func TestJWTMalformedAndClaims(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	if _, err := ts.svc.verifier.VerifyAccessToken("not.a.token"); !errors.Is(err, ErrTokenMalformed) {
		t.Fatalf("malformed = %v, want ErrTokenMalformed", err)
	}
	if _, err := ts.svc.verifier.VerifyAccessToken("a.b"); !errors.Is(err, ErrTokenMalformed) {
		t.Fatalf("2 parts = %v, want ErrTokenMalformed", err)
	}
	if _, err := ts.svc.verifier.VerifyAccessToken(""); !errors.Is(err, ErrTokenMalformed) {
		t.Fatalf("empty = %v, want ErrTokenMalformed", err)
	}

	// Wrong audience.
	token, _ := ts.svc.signer.IssueAccessToken(ctx, "hashid123")
	strict := NewJWTVerifier(&ts.svc.signer.priv.PublicKey, "test-issuer", "other-aud")
	if _, err := strict.VerifyAccessToken(token); !errors.Is(err, ErrTokenInvalid) {
		t.Fatalf("wrong aud = %v, want ErrTokenInvalid", err)
	}
}

func TestParseRSAPEMRoundTrip(t *testing.T) {
	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	pemBytes, err := marshalRSAPrivatePEM(priv)
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	parsed, err := ParseRSAPrivateKeyPEM(pemBytes)
	if err != nil {
		t.Fatalf("ParseRSAPrivateKeyPEM() error = %v", err)
	}
	if parsed.N.Cmp(priv.N) != 0 {
		t.Fatal("parsed key mismatch")
	}
	if _, err := ParseRSAPrivateKeyPEM([]byte("garbage")); err == nil {
		t.Fatal("ParseRSAPrivateKeyPEM() accepted garbage")
	}
}

// ---------------------------------------------------------------------------
// Refresh token rotation + revocation

func TestRefreshRotation(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	raw, err := ts.svc.refresh.Issue(ctx, "hashid123")
	if err != nil {
		t.Fatalf("Issue() error = %v", err)
	}

	newRaw, subject, err := ts.svc.refresh.Refresh(ctx, raw)
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if subject != "hashid123" {
		t.Fatalf("Refresh() subject = %q", subject)
	}
	if newRaw == raw {
		t.Fatal("Refresh() returned the same token (no rotation)")
	}

	// Old token is now invalid (reuse → family revoked).
	if _, _, err := ts.svc.refresh.Refresh(ctx, raw); !errors.Is(err, ErrRefreshReuse) {
		t.Fatalf("replay old token = %v, want ErrRefreshReuse", err)
	}
	// Family revocation kills the rotated token too.
	if _, _, err := ts.svc.refresh.Refresh(ctx, newRaw); !errors.Is(err, ErrRefreshRevoked) {
		t.Fatalf("family-revoked token = %v, want ErrRefreshRevoked", err)
	}
}

func TestRefreshExplicitRevoke(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	raw, _ := ts.svc.refresh.Issue(ctx, "hashid123")
	if err := ts.svc.refresh.Revoke(ctx, raw); err != nil {
		t.Fatalf("Revoke() error = %v", err)
	}
	if _, _, err := ts.svc.refresh.Refresh(ctx, raw); !errors.Is(err, ErrRefreshReuse) {
		t.Fatalf("refresh after revoke = %v, want ErrRefreshReuse", err)
	}
	// Revoking an unknown token is idempotent.
	if err := ts.svc.refresh.Revoke(ctx, "unknown-token"); err != nil {
		t.Fatalf("Revoke(unknown) error = %v", err)
	}
}

func TestRefreshUnknownToken(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	if _, _, err := ts.svc.refresh.Refresh(ctx, "made-up-token"); !errors.Is(err, ErrRefreshNotFound) {
		t.Fatalf("unknown token = %v, want ErrRefreshNotFound", err)
	}
}

func TestRefreshExpired(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	raw, _ := ts.svc.refresh.Issue(ctx, "hashid123")
	// Advance beyond the 30-day TTL.
	ts.svc.SetClock(func() time.Time { return time.Now().Add(31 * 24 * time.Hour) })

	if _, _, err := ts.svc.refresh.Refresh(ctx, raw); !errors.Is(err, ErrRefreshExpired) {
		t.Fatalf("expired refresh = %v, want ErrRefreshExpired", err)
	}
}

func TestRefreshIndependentFamilies(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	rawA, _ := ts.svc.refresh.Issue(ctx, "hashA")
	rawB, _ := ts.svc.refresh.Issue(ctx, "hashB")

	// Revoking family A must not affect family B.
	if err := ts.svc.refresh.Revoke(ctx, rawA); err != nil {
		t.Fatalf("Revoke() error = %v", err)
	}
	if _, subject, err := ts.svc.refresh.Refresh(ctx, rawB); err != nil || subject != "hashB" {
		t.Fatalf("family B refresh = %v/%q, want nil/hashB", err, subject)
	}
}

// marshalRSAPrivatePEM is a test helper that serializes an RSA key to PKCS#8
// PEM using the same stdlib primitives the production code parses.
func marshalRSAPrivatePEM(priv *rsa.PrivateKey) ([]byte, error) {
	der, err := x509.MarshalPKCS8PrivateKey(priv)
	if err != nil {
		return nil, err
	}
	return pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: der}), nil
}

// hmacSHA256 is a test helper implementing the HS256 confusion attack.
func hmacSHA256(key, msg []byte) []byte {
	mac := hmac.New(sha256.New, key)
	mac.Write(msg)
	return mac.Sum(nil)
}

// flipSegment decodes a base64url segment, XORs one byte, and re-encodes it.
// Deterministic tampering for signature/payload integrity tests.
func flipSegment(seg string, byteIdx int) string {
	raw, err := base64.RawURLEncoding.DecodeString(seg)
	if err != nil || len(raw) == 0 {
		return seg
	}
	raw[byteIdx%len(raw)] ^= 0xFF
	return base64.RawURLEncoding.EncodeToString(raw)
}
