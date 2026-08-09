package identity

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"sync"
	"time"
)

// Ed25519 public keys are 32 bytes.
const (
	ed25519PubKeyLen  = 32
	maxDevicesPerUser = 10
)

// Device is a registered device bound to a blind_hash_id via its public key.
type Device struct {
	DeviceID     string    `json:"device_id"`
	PublicKey    string    `json:"public_key"` // base64url-encoded 32-byte Ed25519 key
	RegisteredAt time.Time `json:"registered_at"`
	LastSeenAt   time.Time `json:"last_seen_at"`
}

// Sentinel errors for device registration.
var (
	ErrDeviceInvalidKey = errors.New("device: public key must be a 32-byte Ed25519 key")
	ErrDeviceLimit      = errors.New("device: per-identity device limit reached")
	ErrDeviceNotFound   = errors.New("device: not found")
)

// DeviceStore persists device registrations per blind_hash_id.
//
// NOTE (Task 4.5): the production implementation lands with the PostgreSQL
// schema (devices table) in Task 4.5.
type DeviceStore interface {
	// Register stores or updates (by DeviceID) a device for [blindHashID].
	// It validates the public key format and enforces the per-user cap.
	Register(ctx context.Context, blindHashID string, d Device) error
	// List returns the devices for [blindHashID], newest first.
	List(ctx context.Context, blindHashID string) ([]Device, error)
	// Revoke removes a device.
	Revoke(ctx context.Context, blindHashID, deviceID string) error
}

// InMemoryDeviceStore is a mutex-guarded in-memory DeviceStore.
type InMemoryDeviceStore struct {
	mu      sync.RWMutex
	devices map[string]map[string]Device
}

// NewInMemoryDeviceStore returns an empty store.
func NewInMemoryDeviceStore() *InMemoryDeviceStore {
	return &InMemoryDeviceStore{devices: make(map[string]map[string]Device)}
}

// Register implements DeviceStore.
func (s *InMemoryDeviceStore) Register(_ context.Context, blindHashID string, d Device) error {
	if d.DeviceID == "" {
		return errors.New("device: device_id is required")
	}
	if !ValidPublicKey(d.PublicKey) {
		return ErrDeviceInvalidKey
	}

	s.mu.Lock()
	defer s.mu.Unlock()

	byID := s.devices[blindHashID]
	if byID == nil {
		byID = make(map[string]Device)
		s.devices[blindHashID] = byID
	}
	if _, exists := byID[d.DeviceID]; !exists && len(byID) >= maxDevicesPerUser {
		return ErrDeviceLimit
	}
	now := time.Now().UTC()
	if d.RegisteredAt.IsZero() {
		d.RegisteredAt = now
	}
	d.LastSeenAt = now
	byID[d.DeviceID] = d
	return nil
}

// List implements DeviceStore.
func (s *InMemoryDeviceStore) List(_ context.Context, blindHashID string) ([]Device, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()

	byID := s.devices[blindHashID]
	out := make([]Device, 0, len(byID))
	for _, d := range byID {
		out = append(out, d)
	}
	// Newest first by registration time.
	for i := 1; i < len(out); i++ {
		for j := i; j > 0 && out[j].RegisteredAt.After(out[j-1].RegisteredAt); j-- {
			out[j], out[j-1] = out[j-1], out[j]
		}
	}
	return out, nil
}

// Revoke implements DeviceStore.
func (s *InMemoryDeviceStore) Revoke(_ context.Context, blindHashID, deviceID string) error {
	s.mu.Lock()
	defer s.mu.Unlock()

	byID := s.devices[blindHashID]
	if byID == nil {
		return fmt.Errorf("%w: %s", ErrDeviceNotFound, deviceID)
	}
	if _, ok := byID[deviceID]; !ok {
		return fmt.Errorf("%w: %s", ErrDeviceNotFound, deviceID)
	}
	delete(byID, deviceID)
	return nil
}

// ValidPublicKey reports whether [encoded] is a base64url-encoded 32-byte
// Ed25519 public key. Raw base64 (with padding) is also accepted for
// client compatibility.
func ValidPublicKey(encoded string) bool {
	if encoded == "" {
		return false
	}
	raw, err := base64.RawURLEncoding.DecodeString(encoded)
	if err != nil {
		raw, err = base64.StdEncoding.DecodeString(encoded)
		if err != nil {
			return false
		}
	}
	return len(raw) == ed25519PubKeyLen
}
