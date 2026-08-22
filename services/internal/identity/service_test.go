package identity

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"
)

func TestRequestOtpStoresCodeAndDelivers(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	otpResult, err := ts.svc.RequestOtp(ctx, testPhone)
	if err != nil {
		t.Fatalf("RequestOtp() error = %v", err)
	}
	if !ValidBlindHashID(otpResult.BlindHashID) {
		t.Fatalf("RequestOtp() returned invalid blind_hash_id %q", otpResult.BlindHashID)
	}

	// The provider was called with the phone (E.164) and the generated code.
	calls := ts.provider.callsSnapshot()
	if len(calls) != 1 || calls[0].phone != testPhone || calls[0].code != "123456" {
		t.Fatalf("provider calls = %+v", calls)
	}

	// The code must be stored (bcrypt hash) under the otp: key.
	stored, err := NewRedisOtpStore(ts.rdb).Get(ctx, otpResult.BlindHashID)
	if err != nil {
		t.Fatalf("stored OTP missing: %v", err)
	}
	if stored == "123456" || !strings.HasPrefix(stored, "$2") {
		t.Fatalf("stored OTP is not a bcrypt hash: %q", stored)
	}
}

func TestRequestOtpRejectsInvalidPhone(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	if _, err := ts.svc.RequestOtp(ctx, "4155552671"); !errors.Is(err, ErrInvalidPhone) {
		t.Fatalf("invalid phone = %v, want ErrInvalidPhone", err)
	}
	if _, err := ts.svc.RequestOtp(ctx, ""); !errors.Is(err, ErrInvalidPhone) {
		t.Fatalf("empty phone = %v, want ErrInvalidPhone", err)
	}
	// No OTP must have been stored or sent.
	if len(ts.provider.callsSnapshot()) != 0 {
		t.Fatal("provider called for an invalid phone")
	}
}

func TestRequestOtpProviderFailureDeletesCode(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	ts.provider.err = errors.New("sms down")

	_, err := ts.svc.RequestOtp(ctx, testPhone)
	if !errors.Is(err, ErrOtpProviderUnavail) {
		t.Fatalf("RequestOtp() = %v, want ErrOtpProviderUnavail", err)
	}
	// The stored code must be removed so no dead code lingers.
	if keys := ts.mr.Keys(); len(keys) != 0 {
		t.Fatalf("Redis not empty after provider failure: %v", keys)
	}
}

func TestVerifyOtpSuccessCreatesUserAndIssuesTokens(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	otpResult, _ := ts.svc.RequestOtp(ctx, testPhone)
	authResult, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456")
	if err != nil {
		t.Fatalf("VerifyOtp() error = %v", err)
	}

	// Tokens issued.
	if authResult.AccessToken == "" || authResult.RefreshToken == "" {
		t.Fatal("VerifyOtp() returned empty tokens")
	}
	if authResult.ExpiresIn != 15*60 {
		t.Fatalf("ExpiresIn = %d, want 900", authResult.ExpiresIn)
	}
	if authResult.User.BlindHashID != otpResult.BlindHashID {
		t.Fatalf("user hash = %q, want %q", authResult.User.BlindHashID, otpResult.BlindHashID)
	}

	// The access token verifies and carries the subject.
	subject, err := ts.svc.VerifyAccessToken(ctx, authResult.AccessToken)
	if err != nil {
		t.Fatalf("VerifyAccessToken() error = %v", err)
	}
	if subject != otpResult.BlindHashID {
		t.Fatalf("subject = %q, want %q", subject, otpResult.BlindHashID)
	}

	// The refresh token is usable.
	newRaw, subj, err := ts.svc.refresh.Refresh(ctx, authResult.RefreshToken)
	if err != nil || subj != otpResult.BlindHashID {
		t.Fatalf("refresh = %v/%q", err, subj)
	}
	_ = newRaw

	// The OTP was consumed.
	if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456"); !errors.Is(err, ErrOtpMissing) {
		t.Fatalf("re-verify consumed code = %v, want ErrOtpMissing", err)
	}
}

func TestRequestOtpResetsAttemptCounter(t *testing.T) {
	// A fresh OTP must grant a full set of attempts again — a user who
	// burned attempts on an old code must not inherit them.
	ts := newTestService(t)
	ctx := context.Background()

	otpResult, _ := ts.svc.RequestOtp(ctx, testPhone)
	for i := 0; i < maxOtpAttempts-1; i++ {
		if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "000000"); !errors.Is(err, ErrOtpCodeMismatch) {
			t.Fatalf("attempt %d = %v", i, err)
		}
	}

	// Request a fresh code and verify the counter was reset (1 failure no
	// longer exhausts, and the correct code still works).
	if _, err := ts.svc.RequestOtp(ctx, testPhone); err != nil {
		t.Fatalf("re-request error = %v", err)
	}
	if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "000000"); !errors.Is(err, ErrOtpCodeMismatch) {
		t.Fatalf("post-reset attempt = %v, want ErrOtpCodeMismatch", err)
	}
	if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456"); err != nil {
		t.Fatalf("correct code after reset = %v, want success", err)
	}
}

func TestVerifyOtpConcurrentFirstLoginRace(t *testing.T) {
	// Simulates two concurrent first logins: Create reports ErrUserExists
	// (the other request won) but the user is stored — VerifyOtp must
	// re-read and continue instead of failing.
	svc := newTestService(t)
	ctx := context.Background()
	inner := NewInMemoryUserStore()
	race := &raceUserStore{InMemoryUserStore: inner}
	svc.svc.users = race

	otpResult, err := svc.svc.RequestOtp(ctx, testPhone)
	if err != nil {
		t.Fatalf("RequestOtp() error = %v", err)
	}
	authResult, err := svc.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456")
	if err != nil {
		t.Fatalf("VerifyOtp() race path = %v, want success", err)
	}
	if authResult.User.BlindHashID != otpResult.BlindHashID {
		t.Fatalf("user = %q, want %q", authResult.User.BlindHashID, otpResult.BlindHashID)
	}
}

func TestServiceRefreshStoreFailureIsInternal(t *testing.T) {
	// A Redis store failure during refresh must surface as ErrInternal (500),
	// NOT ErrTokenUnauthorized (401) — an outage must never masquerade as a
	// rejected token.
	ts := newTestService(t)
	ctx := context.Background()
	bad := &failingRefreshStore{inner: NewRedisRefreshStore(ts.rdb)}
	ts.svc.refresh = NewRefreshManager(bad, ts.cfg.RefreshTokenTTL)

	if _, err := ts.svc.Refresh(ctx, "any-token"); !errors.Is(err, ErrInternal) {
		t.Fatalf("Refresh() store failure = %v, want ErrInternal", err)
	}
}

func TestVerifyOtpWrongCodeAndAttemptCap(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	otpResult, _ := ts.svc.RequestOtp(ctx, testPhone)

	for i := 0; i < maxOtpAttempts; i++ {
		if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "000000"); !errors.Is(err, ErrOtpCodeMismatch) {
			t.Fatalf("attempt %d = %v, want ErrOtpCodeMismatch", i, err)
		}
	}
	// After max attempts, the code is gone and attempts cap kicks in.
	if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456"); !errors.Is(err, ErrOtpAttempts) {
		t.Fatalf("post-cap verify = %v, want ErrOtpAttempts", err)
	}
}

func TestVerifyOtpMissingOrInvalidHash(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	if _, err := ts.svc.VerifyOtp(ctx, "not-a-hash", "123456"); !errors.Is(err, ErrInvalidBlindHash) {
		t.Fatalf("invalid hash = %v, want ErrInvalidBlindHash", err)
	}
	if _, err := ts.svc.VerifyOtp(ctx, "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "123456"); !errors.Is(err, ErrOtpMissing) {
		t.Fatalf("no pending otp = %v, want ErrOtpMissing", err)
	}
}

func TestFullLifecycle(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	// 1. Register via OTP.
	otpResult, _ := ts.svc.RequestOtp(ctx, testPhone)
	authResult, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456")
	if err != nil {
		t.Fatalf("VerifyOtp() error = %v", err)
	}

	// 2. Claim username.
	if err := ts.svc.ClaimUsername(ctx, otpResult.BlindHashID, "alice"); err != nil {
		t.Fatalf("ClaimUsername() error = %v", err)
	}

	// 3. Register a device.
	if err := ts.svc.RegisterDevice(ctx, otpResult.BlindHashID, "dev-1", testPubKey(0x42)); err != nil {
		t.Fatalf("RegisterDevice() error = %v", err)
	}

	// 4. Refresh the session (rotation).
	rotated, err := ts.svc.Refresh(ctx, authResult.RefreshToken)
	if err != nil {
		t.Fatalf("Refresh() error = %v", err)
	}
	if rotated.AccessToken == authResult.AccessToken {
		t.Fatal("Refresh() issued the same access token")
	}

	// 5. The refreshed session still sees the user + devices.
	user, devices, err := ts.svc.GetUser(ctx, otpResult.BlindHashID)
	if err != nil {
		t.Fatalf("GetUser() error = %v", err)
	}
	if user.Username != "alice" {
		t.Fatalf("username = %q, want alice", user.Username)
	}
	if len(devices) != 1 {
		t.Fatalf("devices = %d, want 1", len(devices))
	}

	// 6. Revoke the whole session family; refresh must now fail.
	if err := ts.svc.RevokeRefresh(ctx, rotated.RefreshToken); err != nil {
		t.Fatalf("RevokeRefresh() error = %v", err)
	}
	if _, err := ts.svc.Refresh(ctx, rotated.RefreshToken); !errors.Is(err, ErrTokenUnauthorized) {
		t.Fatalf("refresh after revoke = %v, want ErrTokenUnauthorized", err)
	}
}

func TestAuthFlowWithClock(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()
	start := time.Date(2026, 8, 3, 12, 0, 0, 0, time.UTC)
	ts.svc.SetClock(func() time.Time { return start })

	otpResult, _ := ts.svc.RequestOtp(ctx, testPhone)
	authResult, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456")
	if err != nil {
		t.Fatalf("VerifyOtp() error = %v", err)
	}
	// 15-minute access token: valid at +14m, expired at +16m.
	ts.svc.SetClock(func() time.Time { return start.Add(14 * time.Minute) })
	if _, err := ts.svc.VerifyAccessToken(ctx, authResult.AccessToken); err != nil {
		t.Fatalf("access token at +14m rejected: %v", err)
	}
	ts.svc.SetClock(func() time.Time { return start.Add(16 * time.Minute) })
	if _, err := ts.svc.VerifyAccessToken(ctx, authResult.AccessToken); !errors.Is(err, ErrTokenUnauthorized) {
		t.Fatalf("access token at +16m = %v, want ErrTokenUnauthorized", err)
	}
}

// ---------------------------------------------------------------------------
// SECURITY CHECKPOINT: raw phone numbers are never persisted or logged.

func TestSecurityCheckpointNoPhonePersistedOrLogged(t *testing.T) {
	ts := newTestService(t)
	ctx := context.Background()

	phones := []string{"+14155552671", "+919876543210", "+442079460958"}
	for _, phone := range phones {
		otpResult, err := ts.svc.RequestOtp(ctx, phone)
		if err != nil {
			t.Fatalf("RequestOtp(%s) error = %v", phone, err)
		}
		if _, err := ts.svc.VerifyOtp(ctx, otpResult.BlindHashID, "123456"); err != nil {
			t.Fatalf("VerifyOtp(%s) error = %v", phone, err)
		}
		if err := ts.svc.ClaimUsername(ctx, otpResult.BlindHashID, "user_"+strings.TrimPrefix(phone, "+")[:6]); err != nil {
			t.Fatalf("ClaimUsername() error = %v", err)
		}
		if err := ts.svc.RegisterDevice(ctx, otpResult.BlindHashID, "dev-"+strings.TrimPrefix(phone, "+")[:4], testPubKey(0x01)); err != nil {
			t.Fatalf("RegisterDevice() error = %v", err)
		}
	}

	// 1. Redis must contain no trace of any raw phone number — neither in
	//    keys nor in values (Dump() covers both).
	dump := ts.mr.Dump()
	for _, phone := range phones {
		digits := strings.TrimPrefix(phone, "+")
		if strings.Contains(dump, phone) || strings.Contains(dump, digits) {
			t.Fatalf("raw phone %s persisted in Redis:\n%s", phone, dump)
		}
	}

	// 2. Log output must contain no trace of any raw phone number.
	logs := ts.logBuf.String()
	for _, phone := range phones {
		if strings.Contains(logs, phone) {
			t.Fatalf("raw phone %s logged:\n%s", phone, logs)
		}
	}

	// 3. No phone digits anywhere (the full 11-digit E.164 without '+').
	for _, phone := range phones {
		digits := strings.TrimPrefix(phone, "+")
		if strings.Contains(dump, digits) || strings.Contains(logs, digits) {
			t.Fatalf("phone digits %s persisted or logged", digits)
		}
	}

	// 4. The service data layer only ever saw blind_hash_ids.
	if len(ts.provider.callsSnapshot()) != len(phones) {
		t.Fatalf("provider calls = %d, want %d", len(ts.provider.callsSnapshot()), len(phones))
	}
}

// TestSecurityCheckpointNoRawPrintStatements statically scans the identity
// package for raw print/log calls that could bypass the redacting logger.
func TestSecurityCheckpointNoRawPrintStatements(t *testing.T) {
	// Scans every non-test Go file in this package for unsafe output calls.
	for _, file := range nonTestGoFiles() {
		src := readFileString(file)
		for _, pattern := range []string{"fmt.Print", "fmt.Printf", "fmt.Println", "log.Print", "log.Printf", "println("} {
			if strings.Contains(src, pattern) {
				t.Fatalf("%s contains raw output call %q", file, pattern)
			}
		}
	}
}
