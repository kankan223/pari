// Package idempotency implements server-side request deduplication for
// mutation endpoints (Task 5.3).
//
// The Flutter client attaches an `Idempotency-Key` (UUID v4) header to every
// sync mutation (Task 5.2). A retry after a network drop or timeout must not
// apply the mutation twice. This package stores each key's lifecycle in Redis
// (the existing Sentinel-HA client from internal/cache):
//
//	claim      → SET key '{"status":"in_progress"}' NX EX 24h  (atomic)
//	get        → read the current entry (in_progress or completed)
//	complete   → SET key '{"status":"completed",status_code,body,content_type}'
//	clear      → DEL key (on handler failure, so a retry reprocesses)
//
// The middleware decides: missing header = non-idempotent passthrough,
// malformed key = 400, in-progress = 409 Conflict, completed = replay the
// cached response without re-processing, first sight = process then cache.
//
// ZERO-KNOWLEDGE: keys are UUID v4 (122 random bits — never PII) and the
// cache builder rejects anything else before it can reach Redis; the cached
// body is the JSON the handler already returned (blind hashes / statuses,
// never phone numbers).
package idempotency

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"time"

	"github.com/redis/go-redis/v9"
)

// Entry statuses stored in the Redis value.
const (
	StatusInProgress = "in_progress"
	StatusCompleted  = "completed"
)

// Entry is the JSON payload stored under `idempotency:{uuid}`.
type Entry struct {
	Status      string `json:"status"`
	StatusCode  int    `json:"status_code,omitempty"`
	Body        []byte `json:"body,omitempty"` // raw response body (base64 by encoding/json)
	ContentType string `json:"content_type,omitempty"`
}

// Store persists idempotency entries. Implemented by RedisStore; the
// interface exists so the middleware can be tested against miniredis.
type Store interface {
	// Claim atomically reserves [key] for the caller. It returns true only
	// for the single caller that won the SET NX; concurrent callers get
	// false and must Get to observe the in-progress / completed state.
	Claim(ctx context.Context, key string, ttl time.Duration) (bool, error)
	// Get returns the stored entry; ok is false when the key is absent
	// (never claimed, or TTL-expired).
	Get(ctx context.Context, key string) (Entry, bool, error)
	// Complete persists the successful response under [key] so a retry can
	// replay it without re-processing. The TTL is refreshed from completion
	// time so the replay window is [ttl] after the LAST successful run.
	Complete(ctx context.Context, key string, statusCode int, body []byte, contentType string, ttl time.Duration) error
	// Clear removes [key] (used when the handler failed — a retry must be
	// allowed to reprocess).
	Clear(ctx context.Context, key string) error
}

// RedisStore is the go-redis-backed Store (works with the Sentinel-HA client
// produced by cache.NewClient — same *redis.Client type).
type RedisStore struct {
	rdb *redis.Client
}

// NewRedisStore builds a Store over [rdb].
func NewRedisStore(rdb *redis.Client) *RedisStore { return &RedisStore{rdb: rdb} }

// Claim implements Store.
func (s *RedisStore) Claim(ctx context.Context, key string, ttl time.Duration) (bool, error) {
	raw, err := json.Marshal(Entry{Status: StatusInProgress})
	if err != nil {
		return false, fmt.Errorf("idempotency: encode claim: %w", err)
	}
	ok, err := s.rdb.SetNX(ctx, key, raw, ttl).Result()
	if err != nil {
		return false, fmt.Errorf("idempotency: claim %s: %w", key, err)
	}
	return ok, nil
}

// Get implements Store.
func (s *RedisStore) Get(ctx context.Context, key string) (Entry, bool, error) {
	raw, err := s.rdb.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return Entry{}, false, nil
	}
	if err != nil {
		return Entry{}, false, fmt.Errorf("idempotency: get %s: %w", key, err)
	}
	var e Entry
	if err := json.Unmarshal(raw, &e); err != nil {
		return Entry{}, false, fmt.Errorf("idempotency: decode %s: %w", key, err)
	}
	return e, true, nil
}

// Complete implements Store.
func (s *RedisStore) Complete(ctx context.Context, key string, statusCode int, body []byte, contentType string, ttl time.Duration) error {
	raw, err := json.Marshal(Entry{
		Status:      StatusCompleted,
		StatusCode:  statusCode,
		Body:        body,
		ContentType: contentType,
	})
	if err != nil {
		return fmt.Errorf("idempotency: encode complete: %w", err)
	}
	if err := s.rdb.Set(ctx, key, raw, ttl).Err(); err != nil {
		return fmt.Errorf("idempotency: complete %s: %w", key, err)
	}
	return nil
}

// Clear implements Store.
func (s *RedisStore) Clear(ctx context.Context, key string) error {
	if err := s.rdb.Del(ctx, key).Err(); err != nil {
		return fmt.Errorf("idempotency: clear %s: %w", key, err)
	}
	return nil
}
