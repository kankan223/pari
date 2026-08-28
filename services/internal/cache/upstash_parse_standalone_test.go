package cache

import (
	"os"
	"testing"
)

func TestParseUpstashURLRedissScheme(t *testing.T) {
	addr := "rediss://default:gQAAAAAAAjLmAAIgcDEzNmFmMDk0MTUxYzM0M2U3OTVhYjZhZjc2ZDMyNDNmYQ@clear-raccoon-144102.upstash.io:6389"
	base, token, ok := ParseUpstashURL(addr)
	if !ok {
		t.Fatal("expected ok=true for rediss:// URL")
	}
	t.Logf("base=%q token_len=%d", base, len(token))
	if base != "https://clear-raccoon-144102.upstash.io" {
		t.Errorf("unexpected base URL: %q", base)
	}
	if token == "" {
		t.Error("expected non-empty token")
	}
}

func TestParseUpstashURLEnvVars(t *testing.T) {
	os.Setenv("UPSTASH_REDIS_REST_URL", "https://clear-raccoon-144102.upstash.io")
	os.Setenv("UPSTASH_REDIS_REST_TOKEN", "test-token-123")
	defer os.Unsetenv("UPSTASH_REDIS_REST_URL")
	defer os.Unsetenv("UPSTASH_REDIS_REST_TOKEN")

	base, token, ok := ParseUpstashURL("anything")
	if !ok {
		t.Fatal("expected ok=true from env vars")
	}
	t.Logf("base=%q token=%q", base, token)
}
