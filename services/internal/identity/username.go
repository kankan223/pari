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
	ErrUsernameNotFound = errors.New("username: not found or unavailable")
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

// UsernameLookup is the username-search result (Task 6.2): the username plus
// its owner's blind_hash_id — the minimum needed to address a connection
// request. Deliberately NO phone numbers and no device keys.
type UsernameLookup struct {
	Username    string `json:"username"`
	BlindHashID string `json:"blind_hash_id"`
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
	// ListAll returns all actively claimed usernames (OwnerHash != "")
	// with their owner hashes. Used by the user-list endpoint.
	ListAll(ctx context.Context) ([]UsernameLookup, error)
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

// ListAll implements UsernameStore. Returns all actively claimed usernames
// (where OwnerHash is non-empty) sorted alphabetically.
func (s *InMemoryUsernameStore) ListAll(_ context.Context) ([]UsernameLookup, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	var result []UsernameLookup
	for username, rec := range s.usernames {
		if rec.OwnerHash == "" {
			continue // released / cooldown — not listed
		}
		result = append(result, UsernameLookup{
			Username:    username,
			BlindHashID: rec.OwnerHash,
		})
	}
	// Sort alphabetically for deterministic output.
	for i := 0; i < len(result); i++ {
		for j := i + 1; j < len(result); j++ {
			if result[i].Username > result[j].Username {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	return result, nil
}
