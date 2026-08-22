package identity

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"errors"
	"log/slog"
	"os"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/alicebob/miniredis/v2"
	"github.com/redis/go-redis/v9"

	"github.com/kankan223/pari/services/internal/cache"
	"github.com/kankan223/pari/services/internal/logging"
)

// raceUserStore simulates a concurrent first-login race: the user gets
// stored (as if the other request won) but Create reports ErrUserExists.
type raceUserStore struct {
	*InMemoryUserStore
}

func (s *raceUserStore) Create(ctx context.Context, u User) error {
	_ = s.InMemoryUserStore.Create(ctx, u)
	return ErrUserExists
}

// failingRefreshStore simulates a Redis outage during refresh.
type failingRefreshStore struct {
	inner RefreshStore
}

func (s *failingRefreshStore) StoreRefresh(ctx context.Context, tokenHash, entryJSON string, ttl time.Duration) error {
	return s.inner.StoreRefresh(ctx, tokenHash, entryJSON, ttl)
}

func (s *failingRefreshStore) LoadRefresh(ctx context.Context, tokenHash string) (string, error) {
	return "", errors.New("redis connection refused")
}

func (s *failingRefreshStore) DeleteRefresh(ctx context.Context, tokenHash string) error {
	return s.inner.DeleteRefresh(ctx, tokenHash)
}

func (s *failingRefreshStore) RevokedFamilyOf(ctx context.Context, tokenHash string) (string, bool, error) {
	return s.inner.RevokedFamilyOf(ctx, tokenHash)
}

func (s *failingRefreshStore) MarkRevoked(ctx context.Context, tokenHash, familyID string, ttl time.Duration) error {
	return s.inner.MarkRevoked(ctx, tokenHash, familyID, ttl)
}

func (s *failingRefreshStore) IsFamilyRevoked(ctx context.Context, familyID string) (bool, error) {
	return s.inner.IsFamilyRevoked(ctx, familyID)
}

func (s *failingRefreshStore) RevokeFamily(ctx context.Context, familyID string, ttl time.Duration) error {
	return s.inner.RevokeFamily(ctx, familyID, ttl)
}

// nonTestGoFiles lists the non-test .go files in the current package dir.
func nonTestGoFiles() []string {
	entries, err := os.ReadDir(".")
	if err != nil {
		return nil
	}
	var out []string
	for _, e := range entries {
		if !e.IsDir() && strings.HasSuffix(e.Name(), ".go") && !strings.HasSuffix(e.Name(), "_test.go") {
			out = append(out, e.Name())
		}
	}
	return out
}

// readFileString loads a file for static scans (test-only; the path comes
// from our own directory listing, never user input).
func readFileString(name string) string {
	// #nosec G304 -- static scan of this package's own sources.
	b, err := os.ReadFile(name)
	if err != nil {
		return ""
	}
	return string(b)
}

// testPhone is a deterministic E.164 fixture used across the suite.
const testPhone = "+14155552671"

// fakeProvider records delivery calls and can be configured to fail.
type fakeProvider struct {
	mu    sync.Mutex
	calls []providerCall
	err   error
}

type providerCall struct {
	phone string
	code  string
}

func (p *fakeProvider) SendOTP(_ context.Context, phone, code string) error {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.calls = append(p.calls, providerCall{phone: phone, code: code})
	return p.err
}

func (p *fakeProvider) callsSnapshot() []providerCall {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]providerCall, len(p.calls))
	copy(out, p.calls)
	return out
}

// fakeCodeGen returns a fixed code so tests can assert verification paths.
type fakeCodeGen struct {
	code string
	err  error
}

func (f *fakeCodeGen) Generate() (string, error) {
	if f.err != nil {
		return "", f.err
	}
	return f.code, nil
}

// testService bundles a fully wired identity service for tests.
type testService struct {
	svc      *Service
	rdb      cache.RedisClient
	mr       *miniredis.Miniredis
	provider *fakeProvider
	codeGen  *fakeCodeGen
	logBuf   *bytes.Buffer
	cfg      ServiceConfig
}

// newTestService wires the service with lightweight Argon2id params, an RSA
// test key, miniredis-backed stores, and an in-memory data layer.
func newTestService(t *testing.T) *testService {
	t.Helper()

	mr := miniredis.RunT(t)
	// miniredis v2.36 has no Client() helper; connect the pinned go-redis v9
	// client to its ephemeral address.
	rdb := cache.WrapRedis(redis.NewClient(&redis.Options{Addr: mr.Addr()}))

	priv, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate rsa key: %v", err)
	}

	logBuf := &bytes.Buffer{}
	logger := logging.NewRedactingLogger(logBuf, slog.LevelInfo)

	cfg := ServiceConfig{
		OTPTTL:           10 * time.Minute,
		AccessTokenTTL:   15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		UsernameCooldown: 30 * 24 * time.Hour,
		JWTIssuer:        "test-issuer",
		JWTAudience:      "test-audience",
		JWTKid:           "test-kid",
	}

	signer := NewJWTSigner(priv, cfg.JWTKid, cfg.JWTIssuer, cfg.JWTAudience, cfg.AccessTokenTTL)
	verifier := NewJWTVerifier(&priv.PublicKey, cfg.JWTIssuer, cfg.JWTAudience)
	refresh := NewRefreshManager(NewRedisRefreshStore(rdb), cfg.RefreshTokenTTL)

	provider := &fakeProvider{}
	codeGen := &fakeCodeGen{code: "123456"}

	svc := NewService(
		NewStaticSaltProvider([]byte("test_salt_12345")),
		NewRedisOtpStore(rdb),
		provider,
		codeGen,
		NewInMemoryUserStore(),
		NewInMemoryUsernameStore(),
		NewInMemoryDeviceStore(),
		signer,
		verifier,
		refresh,
		cfg,
		logger,
	)
	svc.SetParams(TestParams())

	return &testService{
		svc:      svc,
		rdb:      rdb,
		mr:       mr,
		provider: provider,
		codeGen:  codeGen,
		logBuf:   logBuf,
		cfg:      cfg,
	}
}
