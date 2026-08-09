package events

import (
	"errors"
	"fmt"
	"regexp"
	"sort"
	"strings"
	"time"

	"github.com/kankan223/pari/services/internal/logging"
)

// Registered event subjects (topic schema, Task 4.7).
//
// SECURITY: only subjects registered below may be published — the registry is
// the allowlist that guarantees zero plaintext PII in subject names. Add new
// subjects here (and to the CIVIC_EVENTS stream config) rather than
// hard-coding strings at call sites.
const (
	// SubjectConnectionAccepted fires when a connection request is accepted
	// (relay); both users' devices fan out a "connected" notice.
	SubjectConnectionAccepted = "relay.connection.accepted"

	// SubjectUserRegistered fires after a user completes first-time setup
	// (identity). Reserved for cross-service onboarding flows.
	SubjectUserRegistered = "identity.user.registered"

	// SubjectKarmaUpdated fires when a user's karma changes (karma service).
	SubjectKarmaUpdated = "karma.updated"

	// SubjectSearchSyncRequested fires when the search index needs to sync a
	// user's public content (search service).
	SubjectSearchSyncRequested = "search.sync.requested"
)

// subjectToken matches a single dotted label of a subject: lowercase letters,
// digits, underscores, hyphens.
var subjectTokenRe = regexp.MustCompile(`^[a-z0-9_-]+$`)

// registeredSubjects is the allowlist of publishable subjects.
var registeredSubjects = []string{
	SubjectConnectionAccepted,
	SubjectUserRegistered,
	SubjectKarmaUpdated,
	SubjectSearchSyncRequested,
}

// StreamConfig describes the CIVIC_EVENTS JetStream stream.
type StreamConfig struct {
	Subjects []string
	Storage  StorageType
	MaxAge   time.Duration // from time import below
	MaxMsgs  int64
	MaxBytes int64
}

// DefaultStreamConfig returns the canonical stream configuration capturing
// every registered subject with 30-day retention (mirrors the 30-day offline
// queue TTL).
func DefaultStreamConfig() StreamConfig {
	return StreamConfig{
		Subjects: append([]string(nil), registeredSubjects...),
		Storage:  StorageFile,
		MaxAge:   30 * 24 * time.Hour,
	}
}

// RegisteredSubjects returns the allowlisted subject set (sorted copy).
func RegisteredSubjects() []string {
	out := append([]string(nil), registeredSubjects...)
	sort.Strings(out)
	return out
}

// ValidateSubject enforces the topic schema + zero-PII rule. A subject must:
//
//  1. be a registered allowlisted subject, and
//  2. be non-empty, dotted tokens matching [subjectTokenRe], and
//  3. carry no PII (E.164 phone / e-mail) anywhere in the string.
func ValidateSubject(subject string) error {
	if subject == "" {
		return errors.New("events: empty subject")
	}
	if err := validateSyntax(subject); err != nil {
		return err
	}
	if logging.ContainsPII(subject) {
		return fmt.Errorf("events: subject contains PII: %q", subject)
	}
	for _, s := range registeredSubjects {
		if s == subject {
			return nil
		}
	}
	return fmt.Errorf("events: subject %q is not registered (add it to the topic schema)", subject)
}

func validateSyntax(subject string) error {
	for _, tok := range strings.Split(subject, ".") {
		if !subjectTokenRe.MatchString(tok) {
			return fmt.Errorf("events: invalid subject token %q in %q", tok, subject)
		}
	}
	return nil
}

// ValidatePayload enforces the zero-PII rule on event bodies. Payloads may
// carry only blind_hash_ids and non-PII metadata (JSON, protobuf, opaque
// bytes); E.164 phones and e-mails are rejected outright.
func ValidatePayload(payload []byte) error {
	if logging.ContainsPII(string(payload)) {
		return errors.New("payload contains plaintext PII")
	}
	return nil
}
