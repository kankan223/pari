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
//   - Environment variable UPSTASH_REDIS_REST_URL + UPSTASH_REDIS_REST_TOKEN
//     when REDIS_ADDR contains "upstash" or starts with "https://"
//
// Returns ("", "", false) for standard Redis addresses.
func ParseUpstashURL(addr string) (baseURL, token string, ok bool) {
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
			baseURL = scheme + "://" + u.Host
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

	// Check UPSTASH env vars directly (explicit Upstash configuration)
	if upstashURL := os.Getenv("UPSTASH_REDIS_REST_URL"); upstashURL != "" {
		if upstashToken := os.Getenv("UPSTASH_REDIS_REST_TOKEN"); upstashToken != "" {
			return upstashURL, upstashToken, true
		}
	}

	return "", "", false
}
