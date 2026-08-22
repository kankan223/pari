package idempotency

import (
	"context"
	"sync"
	"time"
)

// InMemoryStore is a development/staging idempotency Store with no
// persistence. Entries are lost on restart — suitable for staging only.
type InMemoryStore struct {
	mu      sync.Mutex
	entries map[string]Entry
}

// NewInMemoryStore builds an empty in-memory idempotency store.
func NewInMemoryStore() *InMemoryStore {
	return &InMemoryStore{entries: make(map[string]Entry)}
}

// Claim implements Store. Always returns true (no concurrent exclusivity
// in-memory — acceptable for dev/staging).
func (s *InMemoryStore) Claim(_ context.Context, key string, _ time.Duration) (bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if _, exists := s.entries[key]; exists {
		return false, nil
	}
	s.entries[key] = Entry{Status: StatusInProgress}
	return true, nil
}

// Get implements Store.
func (s *InMemoryStore) Get(_ context.Context, key string) (Entry, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	e, ok := s.entries[key]
	return e, ok, nil
}

// Complete implements Store.
func (s *InMemoryStore) Complete(_ context.Context, key string, statusCode int, body []byte, contentType string, _ time.Duration) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.entries[key] = Entry{
		Status:      StatusCompleted,
		StatusCode:  statusCode,
		Body:        body,
		ContentType: contentType,
	}
	return nil
}

// Clear implements Store.
func (s *InMemoryStore) Clear(_ context.Context, key string) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	delete(s.entries, key)
	return nil
}
