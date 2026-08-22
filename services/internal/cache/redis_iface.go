// Package cache provides a RedisClient interface that both the go-redis
// native client and the Upstash HTTP client satisfy.
package cache

import (
	"context"
	"time"

	"github.com/redis/go-redis/v9"
)

// Pipeliner is the narrow pipeline interface used by the identity,
// relay, and idempotency stores. It covers only the methods actually
// called in the codebase, avoiding the huge redis.Pipeliner interface.
type Pipeliner interface {
	Exec(ctx context.Context) ([]redis.Cmder, error)
	Incr(ctx context.Context, key string) *redis.IntCmd
	Expire(ctx context.Context, key string, ttl time.Duration) *redis.BoolCmd
	XAdd(ctx context.Context, a *redis.XAddArgs) *redis.StringCmd
	XTrimMinID(ctx context.Context, stream, minID string) *redis.IntCmd
}

// RedisClient is the subset of *redis.Client methods used by the
// identity, relay, and idempotency stores.
type RedisClient interface {
	Set(ctx context.Context, key string, value any, ttl time.Duration) *redis.StatusCmd
	Get(ctx context.Context, key string) *redis.StringCmd
	Del(ctx context.Context, keys ...string) *redis.IntCmd
	Exists(ctx context.Context, keys ...string) *redis.IntCmd
	SetNX(ctx context.Context, key string, value any, ttl time.Duration) *redis.BoolCmd
	Expire(ctx context.Context, key string, ttl time.Duration) *redis.BoolCmd

	Pipeline() Pipeliner

	XAdd(ctx context.Context, a *redis.XAddArgs) *redis.StringCmd
	XRead(ctx context.Context, a *redis.XReadArgs) *redis.XStreamSliceCmd
	XDel(ctx context.Context, stream string, ids ...string) *redis.IntCmd
	XLen(ctx context.Context, stream string) *redis.IntCmd
	XTrimMinID(ctx context.Context, stream, minID string) *redis.IntCmd
}

// --- Adapters for *redis.Client ---

// RedisClientAdapter wraps *redis.Client to satisfy RedisClient.
type RedisClientAdapter struct {
	*redis.Client
}

var _ RedisClient = (*RedisClientAdapter)(nil)

// Pipeline returns a pipelinerAdapter that wraps *redis.Pipeline.
func (a *RedisClientAdapter) Pipeline() Pipeliner {
	return &pipelinerAdapter{p: a.Client.Pipeline()}
}

// pipelinerAdapter wraps redis.Pipeliner to satisfy our Pipeliner.
type pipelinerAdapter struct {
	p redis.Pipeliner
}

var _ Pipeliner = (*pipelinerAdapter)(nil)

func (a *pipelinerAdapter) Exec(ctx context.Context) ([]redis.Cmder, error) {
	return a.p.Exec(ctx)
}
func (a *pipelinerAdapter) Incr(ctx context.Context, key string) *redis.IntCmd {
	return a.p.Incr(ctx, key)
}
func (a *pipelinerAdapter) Expire(ctx context.Context, key string, ttl time.Duration) *redis.BoolCmd {
	return a.p.Expire(ctx, key, ttl)
}
func (a *pipelinerAdapter) XAdd(ctx context.Context, xargs *redis.XAddArgs) *redis.StringCmd {
	return a.p.XAdd(ctx, xargs)
}
func (a *pipelinerAdapter) XTrimMinID(ctx context.Context, stream, minID string) *redis.IntCmd {
	return a.p.XTrimMinID(ctx, stream, minID)
}

// WrapRedis wraps a *redis.Client into a RedisClientAdapter.
// Convenience helper for test setup and main.go composition.
func WrapRedis(c *redis.Client) *RedisClientAdapter {
	return &RedisClientAdapter{Client: c}
}
