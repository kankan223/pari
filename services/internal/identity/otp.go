package identity

import (
	"context"
	"crypto/rand"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
	"golang.org/x/crypto/bcrypt"

	"github.com/kankan223/pari/services/internal/cache"
)

// OTP namespace and policy (Task 4.3): codes live in Redis under
// `otp:{blind_hash_id}` for 10 minutes, stored bcrypt-hashed so a Redis
// compromise never reveals live codes. Attempts are capped to slow
// brute-forcing; the counter shares the OTP's lifetime. Keys are built by
// the validated cache namespace builders (Task 4.6) so a raw phone number
// can never become a Redis key.
const (
	maxOtpAttempts = 5
	otpCodeLength  = 6
)

// ErrOtpNotFound is returned by the store when no pending code exists.
var ErrOtpNotFound = errors.New("otp: no pending code for identity")

// CodeGenerator produces one-time codes.
type CodeGenerator interface {
	Generate() (string, error)
}

// RandomCodeGenerator emits 6-digit codes from crypto/rand (rejection-sampled
// so every digit is uniform).
type RandomCodeGenerator struct{}

// Generate implements CodeGenerator.
func (RandomCodeGenerator) Generate() (string, error) {
	const digits = "0123456789"
	out := make([]byte, otpCodeLength)
	// RandomInt over 10 is not uniform with plain mod; sample from a clean
	// block instead.
	reject := 256 - (256 % len(digits))
	buf := make([]byte, otpCodeLength)
	for i := 0; i < otpCodeLength; i++ {
		for {
			if _, err := rand.Read(buf[i : i+1]); err != nil {
				return "", fmt.Errorf("otp: random source: %w", err)
			}
			if int(buf[i]) < reject {
				out[i] = digits[int(buf[i])%len(digits)]
				break
			}
		}
	}
	return string(out), nil
}

// OtpStore persists pending OTP codes (hash of the code, never the code).
type OtpStore interface {
	// Set stores the bcrypt hash of a code for [blindHashID] with [ttl].
	Set(ctx context.Context, blindHashID, codeHash string, ttl time.Duration) error
	// Get returns the stored code hash, or ErrOtpNotFound.
	Get(ctx context.Context, blindHashID string) (string, error)
	// Delete removes a pending code.
	Delete(ctx context.Context, blindHashID string) error
	// Attempts returns the current failed-attempt count for [blindHashID].
	Attempts(ctx context.Context, blindHashID string) (int, error)
	// RecordAttempt increments the failed-attempt count (sets the TTL on the
	// first attempt) and returns the new count.
	RecordAttempt(ctx context.Context, blindHashID string, ttl time.Duration) (int, error)
	// ClearAttempts removes the attempt counter.
	ClearAttempts(ctx context.Context, blindHashID string) error
}

// RedisOtpStore is the production OtpStore backed by go-redis.
type RedisOtpStore struct {
	rdb *redis.Client
}

// NewRedisOtpStore wraps [rdb].
func NewRedisOtpStore(rdb *redis.Client) *RedisOtpStore {
	return &RedisOtpStore{rdb: rdb}
}

// Set implements OtpStore.
func (s *RedisOtpStore) Set(ctx context.Context, blindHashID, codeHash string, ttl time.Duration) error {
	key, err := cache.OtpKey(blindHashID)
	if err != nil {
		return err
	}
	return s.rdb.Set(ctx, key, codeHash, ttl).Err()
}

// Get implements OtpStore.
func (s *RedisOtpStore) Get(ctx context.Context, blindHashID string) (string, error) {
	key, err := cache.OtpKey(blindHashID)
	if err != nil {
		return "", err
	}
	v, err := s.rdb.Get(ctx, key).Result()
	if errors.Is(err, redis.Nil) {
		return "", ErrOtpNotFound
	}
	if err != nil {
		return "", fmt.Errorf("otp: read store: %w", err)
	}
	return v, nil
}

// Delete implements OtpStore.
func (s *RedisOtpStore) Delete(ctx context.Context, blindHashID string) error {
	key, err := cache.OtpKey(blindHashID)
	if err != nil {
		return err
	}
	return s.rdb.Del(ctx, key).Err()
}

// Attempts implements OtpStore.
func (s *RedisOtpStore) Attempts(ctx context.Context, blindHashID string) (int, error) {
	key, err := cache.OtpAttemptsKey(blindHashID)
	if err != nil {
		return 0, err
	}
	n, err := s.rdb.Get(ctx, key).Int()
	if errors.Is(err, redis.Nil) {
		return 0, nil
	}
	if err != nil {
		return 0, fmt.Errorf("otp: read attempts: %w", err)
	}
	return n, nil
}

// RecordAttempt implements OtpStore.
func (s *RedisOtpStore) RecordAttempt(ctx context.Context, blindHashID string, ttl time.Duration) (int, error) {
	key, err := cache.OtpAttemptsKey(blindHashID)
	if err != nil {
		return 0, err
	}
	pipe := s.rdb.Pipeline()
	incr := pipe.Incr(ctx, key)
	pipe.Expire(ctx, key, ttl)
	if _, err := pipe.Exec(ctx); err != nil {
		return 0, fmt.Errorf("otp: record attempt: %w", err)
	}
	return int(incr.Val()), nil
}

// ClearAttempts implements OtpStore.
func (s *RedisOtpStore) ClearAttempts(ctx context.Context, blindHashID string) error {
	key, err := cache.OtpAttemptsKey(blindHashID)
	if err != nil {
		return err
	}
	return s.rdb.Del(ctx, key).Err()
}

// hashOtpCode bcrypt-hashes a code for storage (cost 10 — OTP codes are
// low-entropy, cost is only a mild deterrent, the 5-attempt cap does the real
// work).
func hashOtpCode(code string) (string, error) {
	h, err := bcrypt.GenerateFromPassword([]byte(code), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("otp: hash code: %w", err)
	}
	return string(h), nil
}
