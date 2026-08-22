package cache

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/redis/go-redis/v9"
)

// TestUpstashGetMissingKey verifies that a GET for a non-existent key
// returns redis.Nil (not a garbage string like "%!v(<nil>)").
// This was the root cause of the identity service returning 500 on
// OTP verify — Upstash returns {"result":null} for missing keys.
func TestUpstashGetMissingKey(t *testing.T) {
	// Mock Upstash: GET /get/missing returns {"result":null} (key doesn't exist).
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/get/missing" {
			w.WriteHeader(200)
			_, _ = w.Write([]byte(`{"result":null}`))
			return
		}
		// GET /get/existing returns the stored value.
		if r.URL.Path == "/get/existing" {
			w.WriteHeader(200)
			_, _ = w.Write([]byte(`{"result":"$2a$10$fakehash"}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	client := NewUpstashClient(srv.URL, "test-token")
	ctx := context.Background()

	// Missing key should return redis.Nil.
	err := client.Get(ctx, "missing").Err()
	if !errors.Is(err, redis.Nil) {
		t.Fatalf("Get(missing) error = %v, want redis.Nil", err)
	}

	// Existing key should return the value.
	val, err := client.Get(ctx, "existing").Result()
	if err != nil {
		t.Fatalf("Get(existing) error = %v", err)
	}
	if val != "$2a$10$fakehash" {
		t.Fatalf("Get(existing) = %q, want $2a$10$fakehash", val)
	}
}

// TestUpstashSetAndGetRoundTrip verifies SET stores and GET retrieves correctly.
func TestUpstashSetAndGetRoundTrip(t *testing.T) {
	store := make(map[string]string)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		path := r.URL.Path

		switch {
		case path == "/set/testkey" || path == "/set/testkey?ex=600":
			// Upstash returns {"result":"OK"}
			_, _ = w.Write([]byte(`{"result":"OK"}`))
			store["testkey"] = "newval"
			return
		case path == "/get/testkey":
			if v, ok := store["testkey"]; ok {
				fmt.Fprintf(w, `{"result":"%s"}`, v)
			} else {
				_, _ = w.Write([]byte(`{"result":null}`))
			}
			return
		case path == "/del/testkey":
			delete(store, "testkey")
			_, _ = w.Write([]byte(`{"result":1}`))
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	client := NewUpstashClient(srv.URL, "test-token")
	ctx := context.Background()

	// Set a value.
	if err := client.Set(ctx, "testkey", "newval", 10*time.Minute).Err(); err != nil {
		t.Fatalf("Set() error = %v", err)
	}

	// Get should return it.
	val, err := client.Get(ctx, "testkey").Result()
	if err != nil {
		t.Fatalf("Get() error = %v", err)
	}
	if val != "newval" {
		t.Fatalf("Get() = %q, want newval", val)
	}

	// Delete.
	n, err := client.Del(ctx, "testkey").Result()
	if err != nil {
		t.Fatalf("Del() error = %v", err)
	}
	if n != 1 {
		t.Fatalf("Del() = %d, want 1", n)
	}

	// Get after delete should return redis.Nil.
	err = client.Get(ctx, "testkey").Err()
	if !errors.Is(err, redis.Nil) {
		t.Fatalf("Get() after Del = %v, want redis.Nil", err)
	}
}

// TestUpstashPipelineIncrExpire verifies the pipeline INCR+EXPIRE path
// used by OTP attempt recording.
func TestUpstashPipelineIncrExpire(t *testing.T) {
	counters := make(map[string]int)
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Type", "application/json")
		if r.URL.Path == "/pipeline" {
			var cmds [][3]any
			_ = json.NewDecoder(r.Body).Decode(&cmds)
			results := make([]any, len(cmds))
			for i, cmd := range cmds {
				switch cmd[0] {
				case "INCR":
					key := cmd[1].(string)
					counters[key]++
					results[i] = map[string]any{"result": counters[key]}
				case "EXPIRE":
					results[i] = map[string]any{"result": true}
				}
			}
			body, _ := json.Marshal(results)
			_, _ = w.Write(body)
			return
		}
		w.WriteHeader(404)
	}))
	defer srv.Close()

	client := NewUpstashClient(srv.URL, "test-token")
	ctx := context.Background()

	pipe := client.Pipeline()
	incr := pipe.Incr(ctx, "attempts:abc")
	pipe.Expire(ctx, "attempts:abc", 10*time.Minute)
	_, err := pipe.Exec(ctx)
	if err != nil {
		t.Fatalf("pipeline Exec() error = %v", err)
	}

	if incr.Val() != 1 {
		t.Fatalf("INCR result = %d, want 1", incr.Val())
	}
}
