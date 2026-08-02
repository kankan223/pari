// Package cache provides client factories for the cache layer.
package cache

import (
	"time"

	"github.com/redis/go-redis/v9"
)

// NewRedis builds a *redis.Client from connection parameters.
//
// The client is returned lazily (it does not dial until the first command),
// which keeps startup free of network I/O.
func NewRedis(addr, password string, db int) *redis.Client {
	return redis.NewClient(&redis.Options{
		Addr:        addr,
		Password:    password,
		DB:          db,
		DialTimeout: 5 * time.Second,
	})
}
