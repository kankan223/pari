// Package logging provides a PII-redacting structured logger shared by the
// Civic Commons services (extracted from internal/identity in Task 4.4).
//
// SECURITY: any string attribute that matches a PII pattern (E.164 phone
// including its URL-encoded form, or an e-mail address) is replaced with
// "[REDACTED]" before it reaches the sink. Services still log only
// blind_hash_ids and event names — this handler is the last line of defense,
// mirroring the gateway's pii_scrubber.lua.
package logging

import (
	"io"
	"log/slog"
	"regexp"
)

var (
	e164Re    = regexp.MustCompile(`\+[1-9]\d{0,3}\d{6,14}`)
	e164URLRe = regexp.MustCompile(`(?i)%2B[1-9][0-9%]{6,20}`)
	emailRe   = regexp.MustCompile(`[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}`)

	// Vault token shapes (Task 4.8): modern hvs. (service) / hvb. (batch) /
	// hvr. (recovery) / hvc. (client) tokens, plus legacy s. tokens. The
	// legacy s. pattern requires a PURE alphanumeric body (real Vault base62
	// tokens) so identifiers like "s.mysql.user_accounts_table" are NOT
	// redacted — over-matching would corrupt legit log fields and wrongly
	// reject event payloads (ContainsPII gates event publishing). Tokens on
	// the X-Vault-Token / Authorization header are always scrubbed
	// (unambiguous).
	vaultTokenRe  = regexp.MustCompile(`(?i)(?:hvs|hvb|hvr|hvc)\.[A-Za-z0-9._\-=]{20,}|(?i)s\.[A-Za-z0-9]{20,}`)
	vaultHeaderRe = regexp.MustCompile(`(?i)(X-Vault-Token|Authorization)\s*[:=]\s*[A-Za-z0-9._\-=/+]+`)

	redactionPatterns = []*regexp.Regexp{e164Re, e164URLRe, emailRe, vaultTokenRe, vaultHeaderRe}
)

// RedactString replaces any PII pattern in [s] with "[REDACTED]".
func RedactString(s string) string {
	for _, re := range redactionPatterns {
		s = re.ReplaceAllString(s, "[REDACTED]")
	}
	return s
}

// ContainsPII reports whether [s] carries any PII pattern (E.164 phone
// including URL-encoded form, or an e-mail address).
func ContainsPII(s string) bool {
	for _, re := range redactionPatterns {
		if re.MatchString(s) {
			return true
		}
	}
	return false
}

// NewRedactingLogger returns a JSON slog.Logger whose string attributes are
// PII-redacted before serialization. [level] controls the minimum level.
func NewRedactingLogger(w io.Writer, level slog.Level) *slog.Logger {
	return slog.New(NewRedactingHandler(w, level))
}

// NewRedactingHandler builds the underlying slog.Handler.
func NewRedactingHandler(w io.Writer, level slog.Level) slog.Handler {
	return slog.NewJSONHandler(w, &slog.HandlerOptions{
		Level: level,
		ReplaceAttr: func(_ []string, a slog.Attr) slog.Attr {
			if a.Value.Kind() == slog.KindString {
				a.Value = slog.StringValue(RedactString(a.Value.String()))
			}
			return a
		},
	})
}
