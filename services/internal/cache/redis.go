// Package cache provides client factories for the cache layer.
package cache

import (
	"context"
	"strings"
	"time"

	"github.com/redis/go-redis/v9"
)

// Options configures a Redis client. Zero values fall back to
// production-safe defaults applied by NewClient.
type Options struct {
	// Addr is the standalone Redis address (host:port). Ignored when
	// SentinelAddrs is non-empty.
	Addr     string
	Password string
	DB       int

	// SentinelAddrs enables Redis Sentinel HA failover (techstack §7.2):
	// when non-empty, the client is a failover client that tracks the
	// elected master and reconnects transparently after a promotion. The
	// go-redis failover client returns the same *redis.Client type, so
	// every store keeps working unchanged.
	SentinelAddrs      []string
	SentinelMasterName string
	SentinelUsername   string
	SentinelPassword   string

	// Connection pool (managed by go-redis).
	PoolSize        int
	MinIdleConns    int
	MaxIdleConns    int
	ConnMaxIdleTime time.Duration

	// Retries for transient failures (network blips, failover windows).
	MaxRetries      int
	MinRetryBackoff time.Duration
	MaxRetryBackoff time.Duration

	// Timeouts.
	DialTimeout  time.Duration
	ReadTimeout  time.Duration
	WriteTimeout time.Duration
	PoolTimeout  time.Duration
}

// defaults fill unset Options with production-safe values.
func (o *Options) defaults() {
	if o.PoolSize <= 0 {
		o.PoolSize = 20
	}
	if o.MinIdleConns <= 0 {
		o.MinIdleConns = 5
	}
	// go-redis: 0 = library default (3), -1 = disable retries. We pin the
	// default to 3 explicitly for a deterministic contract.
	if o.MaxRetries == 0 {
		o.MaxRetries = 3
	}
	if o.MinRetryBackoff <= 0 {
		o.MinRetryBackoff = 8 * time.Millisecond
	}
	if o.MaxRetryBackoff <= 0 {
		o.MaxRetryBackoff = 512 * time.Millisecond
	}
	if o.DialTimeout <= 0 {
		o.DialTimeout = 5 * time.Second
	}
	if o.ReadTimeout <= 0 {
		o.ReadTimeout = 3 * time.Second
	}
	if o.WriteTimeout <= 0 {
		o.WriteTimeout = 3 * time.Second
	}
	if o.PoolTimeout <= 0 {
		o.PoolTimeout = 4 * time.Second
	}
	if o.ConnMaxIdleTime <= 0 {
		o.ConnMaxIdleTime = 5 * time.Minute
	}
	if o.SentinelMasterName == "" {
		o.SentinelMasterName = "civic-master"
	}
}

// NewClient builds a Redis client from [opts]. When SentinelAddrs is
// non-empty the client follows the Sentinel-elected master (HA failover);
// otherwise it is a plain standalone client. The client is returned lazily
// (no network I/O until the first command).
func NewClient(opts Options) *redis.Client {
	opts.defaults()

	if len(opts.SentinelAddrs) > 0 {
		return redis.NewFailoverClient(&redis.FailoverOptions{
			MasterName:       opts.SentinelMasterName,
			SentinelAddrs:    opts.SentinelAddrs,
			SentinelUsername: opts.SentinelUsername,
			SentinelPassword: opts.SentinelPassword,

			Username:        "",
			Password:        opts.Password,
			DB:              opts.DB,
			MaxRetries:      opts.MaxRetries,
			MinRetryBackoff: opts.MinRetryBackoff,
			MaxRetryBackoff: opts.MaxRetryBackoff,
			DialTimeout:     opts.DialTimeout,
			ReadTimeout:     opts.ReadTimeout,
			WriteTimeout:    opts.WriteTimeout,
			PoolSize:        opts.PoolSize,
			PoolTimeout:     opts.PoolTimeout,
			MinIdleConns:    opts.MinIdleConns,
			MaxIdleConns:    opts.MaxIdleConns,
			ConnMaxIdleTime: opts.ConnMaxIdleTime,
		})
	}
	// Parse redis:// or rediss:// URLs (Upstash, Redis Cloud, etc.)
	// redis.ParseURL handles TLS config automatically for rediss:// scheme.
	if strings.HasPrefix(opts.Addr, "redis://") || strings.HasPrefix(opts.Addr, "rediss://") {
		parsed, err := redis.ParseURL(opts.Addr)
		if err == nil {
			// Preserve caller's tuning (pool size, retries, etc.)
			parsed.MaxRetries = opts.MaxRetries
			parsed.MinRetryBackoff = opts.MinRetryBackoff
			parsed.MaxRetryBackoff = opts.MaxRetryBackoff
			parsed.DialTimeout = opts.DialTimeout
			parsed.ReadTimeout = opts.ReadTimeout
			parsed.WriteTimeout = opts.WriteTimeout
			parsed.PoolSize = opts.PoolSize
			parsed.PoolTimeout = opts.PoolTimeout
			parsed.MinIdleConns = opts.MinIdleConns
			parsed.MaxIdleConns = opts.MaxIdleConns
			parsed.ConnMaxIdleTime = opts.ConnMaxIdleTime
			return redis.NewClient(parsed)
		}
	}

	return redis.NewClient(&redis.Options{
		Addr:            opts.Addr,
		Password:        opts.Password,
		MaxRetries:      opts.MaxRetries,
		MinRetryBackoff: opts.MinRetryBackoff,
		MaxRetryBackoff: opts.MaxRetryBackoff,
		DialTimeout:     opts.DialTimeout,
		ReadTimeout:     opts.ReadTimeout,
		WriteTimeout:    opts.WriteTimeout,
		PoolSize:        opts.PoolSize,
		PoolTimeout:     opts.PoolTimeout,
		MinIdleConns:    opts.MinIdleConns,
		MaxIdleConns:    opts.MaxIdleConns,
		ConnMaxIdleTime: opts.ConnMaxIdleTime,
	})
}

// Ping is a health-check probe: it returns nil when the client can reach a
// Redis server within [ctx] (used for startup readiness and liveness checks).
// go-redis validates pooled connections on checkout, so the probe exercises
// the full pool path rather than a fresh dial.
func Ping(ctx context.Context, client *redis.Client) error {
	return client.Ping(ctx).Err()
}
