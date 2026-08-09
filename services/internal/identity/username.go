package identity

import (
	"context"
	"errors"
	"fmt"
	"regexp"
	"sync"
	"time"
)

// Username policy: 3–30 chars, lowercase letters/digits/underscore, must
// start with a letter. Reserved names are never claimable.
var (
	usernameRe       = regexp.MustCompile(`^[a-z][a-z0-9_]{2,29}$`)
	reservedUsername = map[string]struct{}{
		"admin": {}, "administrator": {}, "root": {}, "system": {}, "support": {},
		"civic": {}, "civiccommons": {}, "moderator": {}, "api": {}, "official": {},
		"help": {}, "security": {}, "legal": {}, "team": {}, "staff": {},
	}
)

// Sentinel errors for username claim/release.
var (
	ErrUsernameInvalid  = errors.New("username: invalid format or reserved")
	ErrUsernameTaken    = errors.New("username: already claimed")
	ErrUsernameCooldown = errors.New("username: in 30-day release cooldown")
	ErrUsernameNotOwned = errors.New("username: not owned by this identity")
)

// ValidUsername reports whether [name] satisfies the policy.
func ValidUsername(name string) bool {
	if !usernameRe.MatchString(name) {
		return false
	}
	_, reserved := reservedUsername[name]
	return !reserved
}

// UsernameRecord tracks ownership and release state of one username.
type UsernameRecord struct {
	OwnerHash  string
	ClaimedAt  time.Time
	ReleasedAt time.Time
}

// UsernameStore manages username claim/release with a release cooldown.
//
// NOTE (Task 4.5): the production implementation lands with the PostgreSQL
// schema (usernames table) in Task 4.5.
type UsernameStore interface {
	// Claim attempts to claim [username] for [ownerHash] at [now]. A username
	// released within the last [cooldown] cannot be claimed by anyone
	// (including its previous owner).
	Claim(ctx context.Context, username, ownerHash string, now time.Time, cooldown time.Duration) error
	// Release hands [username] back, starting the cooldown window.
	Release(ctx context.Context, username, ownerHash string, now time.Time) error
	// Get returns the current record.
	Get(ctx context.Context, username string) (UsernameRecord, error)
}

// InMemoryUsernameStore is a mutex-guarded in-memory UsernameStore.
type InMemoryUsernameStore struct {
	mu        sync.RWMutex
	usernames map[string]UsernameRecord
}

// NewInMemoryUsernameStore returns an empty store.
func NewInMemoryUsernameStore() *InMemoryUsernameStore {
	return &InMemoryUsernameStore{usernames: make(map[string]UsernameRecord)}
}

// Claim implements UsernameStore.
func (s *InMemoryUsernameStore) Claim(_ context.Context, username, ownerHash string, now time.Time, cooldown time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	rec, exists := s.usernames[username]
	if !exists {
		s.usernames[username] = UsernameRecord{OwnerHash: ownerHash, ClaimedAt: now}
		return nil
	}
	if rec.OwnerHash == ownerHash {
		return fmt.Errorf("%w: %s already held by this identity", ErrUsernameTaken, username)
	}
	if rec.ReleasedAt.IsZero() {
		return fmt.Errorf("%w: %s", ErrUsernameTaken, username)
	}
	if now.Before(rec.ReleasedAt.Add(cooldown)) {
		return fmt.Errorf("%w: %s (available after %s)", ErrUsernameCooldown, username, rec.ReleasedAt.Add(cooldown).Format(time.RFC3339))
	}
	s.usernames[username] = UsernameRecord{OwnerHash: ownerHash, ClaimedAt: now}
	return nil
}

// Release implements UsernameStore.
func (s *InMemoryUsernameStore) Release(_ context.Context, username, ownerHash string, now time.Time) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	rec, exists := s.usernames[username]
	if !exists || rec.OwnerHash != ownerHash {
		return fmt.Errorf("%w: %s", ErrUsernameNotOwned, username)
	}
	rec.OwnerHash = ""
	rec.ReleasedAt = now
	s.usernames[username] = rec
	return nil
}

// Get implements UsernameStore.
func (s *InMemoryUsernameStore) Get(_ context.Context, username string) (UsernameRecord, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	rec, ok := s.usernames[username]
	if !ok {
		return UsernameRecord{}, fmt.Errorf("%w: %s", ErrUsernameNotOwned, username)
	}
	return rec, nil
}
