package cache

import (
	"net/url"
	"os"
	"strings"
)

// ParseUpstashURL detects whether the Redis address is an Upstash HTTP
// REST endpoint and extracts the base URL and token. It returns ok=true
// when the address should be handled via the Upstash HTTP client
// instead of the go-redis RESP protocol.
//
// Supported formats:
//   - rediss://default:TOKEN@HOST:PORT → ("https://HOST", TOKEN, true)
//   - https://HOST (bare URL) → ("https://HOST", "", true)
//   - UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN env vars
//     (always checked, regardless of REDIS_ADDR format)
//
// Returns ("", "", false) for standard Redis addresses with no Upstash
// env vars.
func ParseUpstashURL(addr string) (baseURL, token string, ok bool) {
	// ALWAYS check Upstash env vars first — this is the most reliable way
	// to detect Upstash on Render free tier where REDIS_ADDR may be set to
	// a RESP IP that times out on port 6389.
	if upstashURL := os.Getenv("UPSTASH_REDIS_REST_URL"); upstashURL != "" {
		if upstashToken := os.Getenv("UPSTASH_REDIS_REST_TOKEN"); upstashToken != "" {
			return upstashURL, upstashToken, true
		}
	}

	// Check if REDIS_ADDR is already a rediss:// URL (standard Upstash format)
	if strings.HasPrefix(addr, "rediss://") || strings.HasPrefix(addr, "redis://") {
		u, err := url.Parse(addr)
		if err != nil {
			return "", "", false
		}
		// Upstash uses rediss:// (TLS). Extract host and token.
		if u.Host != "" {
			scheme := "https"
			if u.Scheme == "redis" {
				scheme = "http"
			}
			// Strip port — Upstash REST API runs on port 443 (standard HTTPS),
			// not 6389 (the RESP protocol port).
			baseURL = scheme + "://" + u.Hostname()
			if u.User != nil {
				token, _ = u.User.Password()
			}
			if token != "" {
				return baseURL, token, true
			}
		}
	}

	// Check if REDIS_ADDR is an HTTPS URL directly
	if strings.HasPrefix(addr, "https://") {
		// Look for the token in UPSTASH_REDIS_REST_TOKEN env var
		token = os.Getenv("UPSTASH_REDIS_REST_TOKEN")
		if token != "" {
			return addr, token, true
		}
		// Also check REDIS_PASSWORD
		token = os.Getenv("REDIS_PASSWORD")
		if token != "" {
			return addr, token, true
		}
	}

	return "", "", false
}
