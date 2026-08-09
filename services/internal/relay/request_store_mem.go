package relay

import (
	"context"
	"sync"
)

// memRequestStore is the in-memory ConnectionRequestStore (production store
// is PostgreSQL, Task 4.5). Updates are compare-and-swap on Status so
// concurrent responders cannot double-transition a request.
type memRequestStore struct {
	mu   sync.Mutex
	byID map[string]ConnectionRequest
	// pending pairs: initiator|target → id (dedupe lookup).
	pending map[string]string
}

// NewMemRequestStore builds an empty in-memory request store.
func NewMemRequestStore() *memRequestStore {
	return &memRequestStore{
		byID:    make(map[string]ConnectionRequest),
		pending: make(map[string]string),
	}
}

// Create implements ConnectionRequestStore.
func (s *memRequestStore) Create(_ context.Context, req ConnectionRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.byID[req.ID] = req
	if req.Status == RequestPending {
		s.pending[req.InitiatorHash+"|"+req.TargetHash] = req.ID
	}
	return nil
}

// Get implements ConnectionRequestStore.
func (s *memRequestStore) Get(_ context.Context, id string) (ConnectionRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	req, ok := s.byID[id]
	if !ok {
		return ConnectionRequest{}, ErrRequestNotFound
	}
	return req, nil
}

// Update implements ConnectionRequestStore (CAS on status). The stored
// request must still be pending — terminal states are immutable and a
// concurrent transition makes this update fail with ErrRequestState.
func (s *memRequestStore) Update(_ context.Context, req ConnectionRequest) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	cur, ok := s.byID[req.ID]
	if !ok {
		return ErrRequestNotFound
	}
	if cur.Status != RequestPending {
		return ErrRequestState
	}
	if req.Status != RequestPending {
		delete(s.pending, req.InitiatorHash+"|"+req.TargetHash)
	}
	s.byID[req.ID] = req
	return nil
}

// FindPending implements ConnectionRequestStore.
func (s *memRequestStore) FindPending(_ context.Context, initiator, target string) (ConnectionRequest, bool, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	id, ok := s.pending[initiator+"|"+target]
	if !ok {
		return ConnectionRequest{}, false, nil
	}
	return s.byID[id], true, nil
}

// ListFor implements ConnectionRequestStore.
func (s *memRequestStore) ListFor(_ context.Context, hash string) ([]ConnectionRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	var out []ConnectionRequest
	for _, req := range s.byID {
		if req.InitiatorHash == hash || req.TargetHash == hash {
			out = append(out, req)
		}
	}
	return out, nil
}

// ListPending implements ConnectionRequestStore.
func (s *memRequestStore) ListPending(_ context.Context) ([]ConnectionRequest, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	out := make([]ConnectionRequest, 0, len(s.pending))
	for _, id := range s.pending {
		out = append(out, s.byID[id])
	}
	return out, nil
}
