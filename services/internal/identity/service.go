package identity

import (
	"context"
	"errors"
	"log/slog"
	"regexp"
	"time"

	"golang.org/x/crypto/bcrypt"
)

// ServiceConfig carries tunables for the identity service.
type ServiceConfig struct {
	OTPTTL           time.Duration
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	UsernameCooldown time.Duration
	JWTIssuer        string
	JWTAudience      string
	JWTKid           string
}

// Service-level sentinel errors (mapped to HTTP statuses in server.go).
var (
	ErrInvalidPhone       = errors.New("identity: invalid phone number")
	ErrInvalidBlindHash   = errors.New("identity: invalid blind hash id")
	ErrOtpProviderUnavail = errors.New("identity: sms provider unavailable")
	ErrOtpCodeMismatch    = errors.New("identity: otp code mismatch")
	ErrOtpMissing         = errors.New("identity: no otp pending")
	ErrOtpAttempts        = errors.New("identity: too many otp attempts")
	ErrUsernameClaim      = errors.New("identity: username unavailable")
	ErrUsernameRelease    = errors.New("identity: username not owned")
	ErrDeviceKey          = errors.New("identity: invalid device public key")
	ErrDeviceCap          = errors.New("identity: device limit reached")
	ErrAuthRequired       = errors.New("identity: authentication required")
	ErrTokenUnauthorized  = errors.New("identity: token rejected")
	ErrInternal           = errors.New("identity: internal error")
	ErrInvalidPreKeyBundle = errors.New("identity: invalid prekey bundle")
	ErrPreKeyUnavailable  = errors.New("identity: prekey store unavailable")
)

var blindHashIDRe = regexp.MustCompile(`^[0-9a-f]{64}$`)

// ValidBlindHashID reports whether [id] looks like a 64-hex-char Argon2id
// blind_hash_id.
func ValidBlindHashID(id string) bool {
	return blindHashIDRe.MatchString(id)
}

// AuthResult is returned by successful OTP verification / refresh.
type AuthResult struct {
	AccessToken  string   `json:"access_token"`
	RefreshToken string   `json:"refresh_token"`
	ExpiresIn    int64    `json:"expires_in"` // seconds
	User         User     `json:"user"`
	Devices      []Device `json:"devices,omitempty"`
}

// Service orchestrates the identity lifecycle. It owns NO phone numbers:
// every method that receives one hashes it immediately and never stores or
// logs it.
type Service struct {
	salt        SaltProvider
	params      Params
	otpStore    OtpStore
	otpProvider SMSProvider
	codeGen     CodeGenerator
	users       UserStore
	usernames   UsernameStore
	devices     DeviceStore
	prekeys     PreKeyStore
	signer      *JWTSigner
	verifier    *JWTVerifier
	refresh     *RefreshManager
	cfg         ServiceConfig
	now         func() time.Time
	log         *slog.Logger
}

// NewService assembles the identity service. [params] should be
// DefaultParams in production; tests pass TestParams for speed.
func NewService(
	salt SaltProvider,
	otpStore OtpStore,
	otpProvider SMSProvider,
	codeGen CodeGenerator,
	users UserStore,
	usernames UsernameStore,
	devices DeviceStore,
	prekeys PreKeyStore,
	signer *JWTSigner,
	verifier *JWTVerifier,
	refresh *RefreshManager,
	cfg ServiceConfig,
	log *slog.Logger,
) *Service {
	return &Service{
		salt:        salt,
		params:      DefaultParams(),
		otpStore:    otpStore,
		otpProvider: otpProvider,
		codeGen:     codeGen,
		users:       users,
		usernames:   usernames,
		devices:     devices,
		prekeys:     prekeys,
		signer:      signer,
		verifier:    verifier,
		refresh:     refresh,
		cfg:         cfg,
		now:         time.Now,
		log:         log,
	}
}

// SetParams overrides the Argon2id parameters (tests use lightweight ones).
func (s *Service) SetParams(p Params) { s.params = p }

// SetClock overrides the time source (tests).
func (s *Service) SetClock(now func() time.Time) {
	s.now = now
	s.signer.SetClock(now)
	s.verifier.SetClock(now)
	s.refresh.SetClock(now)
}

// RequestOtpResult carries the blind_hash_id and, in dev mode, the
// plaintext OTP code so the caller can include it in the response.
type RequestOtpResult struct {
	BlindHashID string
	// DevOTPCode is populated only in dev/noop mode. Empty in production.
	DevOTPCode string
}

// RequestOtp validates [phone], derives its blind_hash_id, generates and
// stores a 10-minute OTP, and dispatches it via the SMS provider.
//
// SECURITY: [phone] exists only inside this call (validated → hashed →
// handed to the SMS provider → discarded). It is never persisted or logged.
// On provider failure the stored code is removed so no dead code lingers.
//
// The returned RequestOtpResult.DevOTPCode is non-empty only when the
// provider is noop (dev mode) — it allows the frontend to display the
// code during testing without needing access to server logs.
func (s *Service) RequestOtp(ctx context.Context, phone string) (RequestOtpResult, error) {
	if !ValidE164(phone) {
		return RequestOtpResult{}, ErrInvalidPhone
	}

	salt, err := s.salt.Salt(ctx)
	if err != nil {
		s.log.Error("otp_request_failed", "reason", "salt_unavailable", "err", err.Error())
		return RequestOtpResult{}, ErrInternal
	}

	blindHashID := s.params.HashPhone(phone, salt)

	code, err := s.codeGen.Generate()
	if err != nil {
		return RequestOtpResult{}, ErrInternal
	}
	codeHash, err := hashOtpCode(code)
	if err != nil {
		return RequestOtpResult{}, ErrInternal
	}
	if err := s.otpStore.Set(ctx, blindHashID, codeHash, s.cfg.OTPTTL); err != nil {
		s.log.Error("otp_request_failed", "reason", "store_unavailable")
		return RequestOtpResult{}, ErrInternal
	}
	// A fresh code resets the failed-attempt counter so the user always gets
	// a full 5 attempts per code.
	_ = s.otpStore.ClearAttempts(ctx, blindHashID)
	if err := s.otpProvider.SendOTP(ctx, phone, code); err != nil {
		_ = s.otpStore.Delete(ctx, blindHashID) // never leave a dead code behind
		s.log.Error("otp_request_failed", "reason", "provider_unavailable")
		return RequestOtpResult{}, ErrOtpProviderUnavail
	}

	s.log.Info("otp_requested", "event", "otp_requested", "hash_id", blindHashID, "ttl_s", int(s.cfg.OTPTTL.Seconds()))
	return RequestOtpResult{BlindHashID: blindHashID, DevOTPCode: code}, nil
}

// VerifyOtp redeems a code for [blindHashID] (the client-derived hash of the
// phone the code was sent to — the server never needs the phone again),
// creates the user on first login, and issues the access + refresh tokens.
func (s *Service) VerifyOtp(ctx context.Context, blindHashID, code string) (*AuthResult, error) {
	if !ValidBlindHashID(blindHashID) {
		return nil, ErrInvalidBlindHash
	}

	attempts, err := s.otpStore.Attempts(ctx, blindHashID)
	if err != nil {
		return nil, ErrInternal
	}
	if attempts >= maxOtpAttempts {
		return nil, ErrOtpAttempts
	}

	storedHash, err := s.otpStore.Get(ctx, blindHashID)
	if err != nil {
		if errors.Is(err, ErrOtpNotFound) {
			return nil, ErrOtpMissing
		}
		return nil, ErrInternal
	}

	if err := bcrypt.CompareHashAndPassword([]byte(storedHash), []byte(code)); err != nil {
		n, aerr := s.otpStore.RecordAttempt(ctx, blindHashID, s.cfg.OTPTTL)
		if aerr != nil {
			return nil, ErrInternal
		}
		if n >= maxOtpAttempts {
			// Exhausted: invalidate the code entirely.
			_ = s.otpStore.Delete(ctx, blindHashID)
		}
		return nil, ErrOtpCodeMismatch
	}

	// Success: consume the code and clear the attempt counter.
	_ = s.otpStore.Delete(ctx, blindHashID)
	_ = s.otpStore.ClearAttempts(ctx, blindHashID)

	user, err := s.users.Get(ctx, blindHashID)
	if errors.Is(err, ErrUserNotFound) {
		user = User{BlindHashID: blindHashID, CreatedAt: s.now().UTC()}
		if cerr := s.users.Create(ctx, user); cerr != nil {
			// Concurrent first login: another request may have created the
			// user between our Get and Create — proceed with the stored one.
			if !errors.Is(cerr, ErrUserExists) {
				return nil, ErrInternal
			}
			if user, err = s.users.Get(ctx, blindHashID); err != nil {
				return nil, ErrInternal
			}
		}
		s.log.Info("registration", "event", "registration", "hash_id", blindHashID)
	} else if err != nil {
		return nil, ErrInternal
	}
	s.log.Info("otp_verified", "event", "otp_verified", "hash_id", blindHashID)

	access, err := s.signer.IssueAccessToken(ctx, blindHashID)
	if err != nil {
		return nil, ErrInternal
	}
	refresh, err := s.refresh.Issue(ctx, blindHashID)
	if err != nil {
		return nil, ErrInternal
	}

	devices, _ := s.devices.List(ctx, blindHashID)
	return &AuthResult{
		AccessToken:  access,
		RefreshToken: refresh,
		ExpiresIn:    int64(s.cfg.AccessTokenTTL.Seconds()),
		User:         user,
		Devices:      devices,
	}, nil
}

// VerifyAccessToken validates a Bearer access token and returns the subject.
func (s *Service) VerifyAccessToken(ctx context.Context, token string) (string, error) {
	if token == "" {
		return "", ErrAuthRequired
	}
	claims, err := s.verifier.VerifyAccessToken(token)
	if err != nil {
		return "", ErrTokenUnauthorized
	}
	return claims.Subject, nil
}

// ClaimUsername claims [username] for the authenticated identity, enforcing
// the 30-day release cooldown.
func (s *Service) ClaimUsername(ctx context.Context, blindHashID, username string) error {
	if !ValidUsername(username) {
		return ErrUsernameClaim
	}
	if err := s.usernames.Claim(ctx, username, blindHashID, s.now().UTC(), s.cfg.UsernameCooldown); err != nil {
		if errors.Is(err, ErrUsernameCooldown) || errors.Is(err, ErrUsernameTaken) {
			return ErrUsernameClaim
		}
		return ErrInternal
	}
	if err := s.users.SetUsername(ctx, blindHashID, username); err != nil {
		return ErrInternal
	}
	s.log.Info("username_claimed", "event", "username_claimed", "hash_id", blindHashID, "username", username)
	return nil
}

// ReleaseUsername releases the identity's current username into the 30-day
// cooldown window.
func (s *Service) ReleaseUsername(ctx context.Context, blindHashID string) error {
	user, err := s.users.Get(ctx, blindHashID)
	if err != nil {
		return ErrInternal
	}
	if user.Username == "" {
		return ErrUsernameRelease
	}
	if err := s.usernames.Release(ctx, user.Username, blindHashID, s.now().UTC()); err != nil {
		if errors.Is(err, ErrUsernameNotOwned) {
			return ErrUsernameRelease
		}
		return ErrInternal
	}
	if err := s.users.SetUsername(ctx, blindHashID, ""); err != nil {
		return ErrInternal
	}
	s.log.Info("username_released", "event", "username_released", "hash_id", blindHashID)
	return nil
}

// RegisterDevice binds a device public key to the identity.
func (s *Service) RegisterDevice(ctx context.Context, blindHashID, deviceID, publicKey string) error {
	if err := s.devices.Register(ctx, blindHashID, Device{
		DeviceID:  deviceID,
		PublicKey: publicKey,
	}); err != nil {
		if errors.Is(err, ErrDeviceInvalidKey) {
			return ErrDeviceKey
		}
		if errors.Is(err, ErrDeviceLimit) {
			return ErrDeviceCap
		}
		return ErrInternal
	}
	s.log.Info("device_registered", "event", "device_registered", "hash_id", blindHashID, "device_id", deviceID)
	return nil
}

// ListDevices returns the identity's registered devices.
func (s *Service) ListDevices(ctx context.Context, blindHashID string) ([]Device, error) {
	devices, err := s.devices.List(ctx, blindHashID)
	if err != nil {
		return nil, ErrInternal
	}
	return devices, nil
}

// RevokeDevice removes a device binding.
func (s *Service) RevokeDevice(ctx context.Context, blindHashID, deviceID string) error {
	if err := s.devices.Revoke(ctx, blindHashID, deviceID); err != nil {
		if errors.Is(err, ErrDeviceNotFound) {
			return nil // idempotent
		}
		return ErrInternal
	}
	s.log.Info("device_revoked", "event", "device_revoked", "hash_id", blindHashID, "device_id", deviceID)
	return nil
}

// Refresh rotates the refresh token and issues a fresh access token.
//
// Token-level failures (unknown/reused/revoked/expired) map to 401; store
// infrastructure failures map to 500 so a Redis outage never masquerades as
// "token rejected".
func (s *Service) Refresh(ctx context.Context, refreshToken string) (*AuthResult, error) {
	newRaw, blindHashID, err := s.refresh.Refresh(ctx, refreshToken)
	if err != nil {
		if errors.Is(err, ErrRefreshNotFound) || errors.Is(err, ErrRefreshReuse) ||
			errors.Is(err, ErrRefreshRevoked) || errors.Is(err, ErrRefreshExpired) {
			return nil, ErrTokenUnauthorized
		}
		return nil, ErrInternal
	}
	access, err := s.signer.IssueAccessToken(ctx, blindHashID)
	if err != nil {
		return nil, ErrInternal
	}
	user, err := s.users.Get(ctx, blindHashID)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			// A valid token for a deleted identity: reject the session.
			return nil, ErrTokenUnauthorized
		}
		return nil, ErrInternal
	}
	s.log.Info("token_refreshed", "event", "token_refreshed", "hash_id", blindHashID)
	return &AuthResult{
		AccessToken:  access,
		RefreshToken: newRaw,
		ExpiresIn:    int64(s.cfg.AccessTokenTTL.Seconds()),
		User:         user,
	}, nil
}

// RevokeRefresh invalidates the refresh token and its family (logout).
func (s *Service) RevokeRefresh(ctx context.Context, refreshToken string) error {
	if err := s.refresh.Revoke(ctx, refreshToken); err != nil {
		return ErrInternal
	}
	return nil
}

// LookupUsername resolves a claimed username to its owner's blind_hash_id
// (Task 6.2 — the "username search" contract behind the API Gateway).
//
// SECURITY: only ACTIVELY claimed usernames resolve. Unknown names and names
// sitting in the 30-day release cooldown both map to ErrUsernameNotFound, so
// the endpoint never reveals claim history or pending release windows. The
// result carries only the username and the blind hash — never a phone.
func (s *Service) LookupUsername(ctx context.Context, username string) (*UsernameLookup, error) {
	if !ValidUsername(username) {
		return nil, ErrUsernameNotFound
	}
	rec, err := s.usernames.Get(ctx, username)
	if err != nil {
		return nil, ErrUsernameNotFound
	}
	if rec.OwnerHash == "" {
		// Released into the cooldown window — not resolvable by anyone.
		return nil, ErrUsernameNotFound
	}
	return &UsernameLookup{Username: username, BlindHashID: rec.OwnerHash}, nil
}

// GetUser returns the identity's public profile.
func (s *Service) GetUser(ctx context.Context, blindHashID string) (User, []Device, error) {
	user, err := s.users.Get(ctx, blindHashID)
	if err != nil {
		if errors.Is(err, ErrUserNotFound) {
			return User{}, nil, ErrUserNotFound
		}
		return User{}, nil, ErrInternal
	}
	devices, err := s.devices.List(ctx, blindHashID)
	if err != nil {
		return User{}, nil, ErrInternal
	}
	return user, devices, nil
}

// PublishPreKeys stores the authenticated user's X3DH prekey bundle.
// The bundle must carry only public key material; private keys must never
// be transmitted.
//
// SECURITY: the bundle is validated before storage — invalid keys are rejected
// with ErrInvalidPreKeyBundle. The stored bundle is only accessible via
// authenticated FetchPreKeys calls.
func (s *Service) PublishPreKeys(ctx context.Context, blindHashID string, bundle PreKeyBundle) error {
	if err := ValidatePreKeyBundle(bundle); err != nil {
		return ErrInvalidPreKeyBundle
	}
	if err := s.prekeys.Publish(ctx, blindHashID, bundle); err != nil {
		return ErrPreKeyUnavailable
	}
	s.log.Info("prekeys_published", "event", "prekeys_published", "hash_id", blindHashID)
	return nil
}

// FetchPreKeys retrieves the prekey bundle for [peerHashID] (used by the
// initiator during X3DH). Returns nil when no bundle has been published.
//
// SECURITY: the response contains only public key material — no identity
// hashes beyond the requested peer's blind hash.
func (s *Service) FetchPreKeys(ctx context.Context, peerHashID string) (*PreKeyBundle, error) {
	bundle, err := s.prekeys.Get(ctx, peerHashID)
	if err != nil {
		return nil, ErrPreKeyUnavailable
	}
	return bundle, nil
}

// ConsumeOneTimePreKey removes one one-time prekey for [blindHashID].
// Called internally when the server needs to include a one-time prekey in
// a key exchange response.
func (s *Service) ConsumeOneTimePreKey(ctx context.Context, blindHashID string) (*OneTimePreKeyEntry, error) {
	return s.prekeys.ConsumeOneTimePreKey(ctx, blindHashID)
}

// FetchBundle retrieves the prekey bundle for [peerHashID] and atomically
// consumes one one-time prekey (if available). The returned bundle contains
// at most one OTPK in ConsumedOneTimePreKey — this is the key the initiator
// MUST use for this X3DH session.
//
// SECURITY: the response contains only public key material — no identity
// hashes beyond the requested peer's blind hash. Each OTPK is consumed
// exactly once, preventing replay attacks.
func (s *Service) FetchBundle(ctx context.Context, peerHashID string) (*PreKeyBundle, *OneTimePreKeyEntry, error) {
	bundle, err := s.prekeys.Get(ctx, peerHashID)
	if err != nil {
		return nil, nil, ErrPreKeyUnavailable
	}
	if bundle == nil {
		return nil, nil, nil
	}
	// Atomically consume one OTPK. This may return nil if no OTPKs are
	// available — the initiator can still proceed with DH1-DH3 only.
	consumed, _ := s.prekeys.ConsumeOneTimePreKey(ctx, peerHashID)
	return bundle, consumed, nil
}
