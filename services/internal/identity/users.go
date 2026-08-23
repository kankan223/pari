package identity

import (
	"context"
	"errors"
	"fmt"
	"sync"
	"time"
)

// User is the minimum-claim identity record. It deliberately contains NO
// phone number — the only identifier is the Argon2id blind_hash_id.
type User struct {
	BlindHashID      string    `json:"blind_hash_id"`
	Username         string    `json:"username,omitempty"`
	AvatarURL        string    `json:"avatar_url,omitempty"`
	StatusText       string    `json:"status_text,omitempty"`
	StatusVisibility string    `json:"status_visibility,omitempty"` // online, away, invisible
	CreatedAt        time.Time `json:"created_at"`
}

// Sentinel errors for the user store.
var (
	ErrUserNotFound = errors.New("user: not found")
	ErrUserExists   = errors.New("user: already exists")
)

// UserStore persists identity records.
//
// NOTE (Task 4.5): the production implementation lands with the PostgreSQL
// schema (users table) in Task 4.5. The in-memory store below is the current
// implementation and the unit-test target.
type UserStore interface {
	Create(ctx context.Context, u User) error
	Get(ctx context.Context, blindHashID string) (User, error)
	SetUsername(ctx context.Context, blindHashID, username string) error
	SetProfile(ctx context.Context, blindHashID string, avatarURL, statusText, statusVisibility string) error
	// List returns all users. Used by the user-list endpoint.
	List(ctx context.Context) ([]User, error)
}

// InMemoryUserStore is a mutex-guarded in-memory UserStore.
type InMemoryUserStore struct {
	mu    sync.RWMutex
	users map[string]User
}

// NewInMemoryUserStore returns an empty store.
func NewInMemoryUserStore() *InMemoryUserStore {
	return &InMemoryUserStore{users: make(map[string]User)}
}

// Create implements UserStore.
func (s *InMemoryUserStore) Create(_ context.Context, u User) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, ok := s.users[u.BlindHashID]; ok {
		return fmt.Errorf("%w: %s", ErrUserExists, u.BlindHashID)
	}
	s.users[u.BlindHashID] = u
	return nil
}

// Get implements UserStore.
func (s *InMemoryUserStore) Get(_ context.Context, blindHashID string) (User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	u, ok := s.users[blindHashID]
	if !ok {
		return User{}, fmt.Errorf("%w: %s", ErrUserNotFound, blindHashID)
	}
	return u, nil
}

// SetUsername implements UserStore.
func (s *InMemoryUserStore) SetUsername(_ context.Context, blindHashID, username string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[blindHashID]
	if !ok {
		return fmt.Errorf("%w: %s", ErrUserNotFound, blindHashID)
	}
	u.Username = username
	s.users[blindHashID] = u
	return nil
}

// SetProfile implements UserStore.
func (s *InMemoryUserStore) SetProfile(_ context.Context, blindHashID string, avatarURL, statusText, statusVisibility string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	u, ok := s.users[blindHashID]
	if !ok {
		return fmt.Errorf("%w: %s", ErrUserNotFound, blindHashID)
	}
	u.AvatarURL = avatarURL
	u.StatusText = statusText
	u.StatusVisibility = statusVisibility
	s.users[blindHashID] = u
	return nil
}

// List implements UserStore. Returns all users sorted by created_at.
func (s *InMemoryUserStore) List(_ context.Context) ([]User, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	result := make([]User, 0, len(s.users))
	for _, u := range s.users {
		result = append(result, u)
	}
	// Sort by created_at for deterministic output.
	for i := 0; i < len(result); i++ {
		for j := i + 1; j < len(result); j++ {
			if result[i].CreatedAt.After(result[j].CreatedAt) {
				result[i], result[j] = result[j], result[i]
			}
		}
	}
	return result, nil
}
