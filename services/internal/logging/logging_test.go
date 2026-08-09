package logging

import (
	"bytes"
	"log/slog"
	"strings"
	"testing"
)

func TestRedactString(t *testing.T) {
	cases := []struct {
		in   string
		want string
	}{
		{"call +14155552671 now", "call [REDACTED] now"},
		{"+919876543210", "[REDACTED]"},
		{"noreply@civiccommons.org", "[REDACTED]"},
		{"%2B14155552671", "[REDACTED]"},
		{"abc123", "abc123"}, // untouched
		{"0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef", "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"}, // blind hash preserved
		{"a+b@example.com", "[REDACTED]"},
	}
	for _, c := range cases {
		if got := RedactString(c.in); got != c.want {
			t.Errorf("RedactString(%q) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestRedactingLoggerScrubsPhone(t *testing.T) {
	var buf bytes.Buffer
	logger := NewRedactingLogger(&buf, slog.LevelInfo)
	logger.Info("debug payload", "phone", "+14155552671", "email", "user@example.com")
	out := buf.String()
	if strings.Contains(out, "+14155552671") || strings.Contains(out, "user@example.com") {
		t.Fatalf("logger leaked PII: %s", out)
	}
	if !strings.Contains(out, "[REDACTED]") {
		t.Fatalf("logger did not emit redaction markers: %s", out)
	}
}

func TestRedactingLoggerKeepsBlindHash(t *testing.T) {
	const hashID = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	var buf bytes.Buffer
	logger := NewRedactingLogger(&buf, slog.LevelInfo)
	logger.Info("audit", "event", "otp_requested", "hash_id", hashID)
	out := buf.String()
	if !strings.Contains(out, hashID) {
		t.Fatalf("blind_hash_id must survive logging: %s", out)
	}
	if strings.Contains(out, "[REDACTED]") {
		t.Fatalf("blind_hash_id must not be redacted: %s", out)
	}
}

// Task 4.8 SECURITY CHECKPOINT: Vault tokens and auth headers must be
// redacted before they reach any log sink. The security property is that no
// token-shaped value survives; exact output text is not asserted (the header
// name itself is not secret).
func TestRedactStringVaultSecrets(t *testing.T) {
	leaks := []string{
		"token=hvs.ABCDEF0123456789abcdef0123456789",
		"legacy=s.abcdef0123456789abcdef0123456789abcdef",
		"X-Vault-Token: hvs.ABCDEF0123456789abcdef",
		"Authorization: Bearer hvs.ABCDEF0123456789abcdef0123456789",
		"X-Vault-Token=raw-token-value-1234567890",
	}
	for _, in := range leaks {
		got := RedactString(in)
		if !strings.Contains(got, "[REDACTED]") {
			t.Errorf("RedactString(%q) produced no redaction marker: %q", in, got)
		}
		// No token fragment may survive.
		for _, frag := range []string{"hvs.", "s.abcdef0123456789abcdef", "raw-token-value"} {
			if strings.Contains(got, frag) {
				t.Errorf("RedactString(%q) leaked %q: %q", in, frag, got)
			}
		}
	}
	// Non-secret lines are untouched.
	for _, in := range []string{"plain hvs. not a token", "ordinary log line"} {
		if got := RedactString(in); strings.Contains(got, "[REDACTED]") {
			t.Errorf("RedactString(%q) over-redacted: %q", in, got)
		}
	}
}

func TestRedactingLoggerScrubsVaultToken(t *testing.T) {
	var buf bytes.Buffer
	logger := NewRedactingLogger(&buf, slog.LevelInfo)
	logger.Info("vault event", "token", "hvs.ABCDEF0123456789abcdef0123456789", "path", "identity/argon2_salt")
	out := buf.String()
	if strings.Contains(out, "hvs.ABCDEF0123456789abcdef") {
		t.Fatalf("logger leaked vault token: %s", out)
	}
	if !strings.Contains(out, "[REDACTED]") {
		t.Fatalf("logger did not emit redaction marker: %s", out)
	}
}
