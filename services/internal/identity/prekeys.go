package identity

import (
	"context"
	"encoding/base64"
	"errors"
	"sync"
)

// X3DH prekey bundle constants.
const (
	// Ed25519 signature length for signed prekey signatures.
	ed25519SignatureLen = 64
	// Curve25519 public key length.
	curve25519PubKeyLen = 32
	// Maximum one-time prekeys per user.
	maxOneTimePreKeys = 100
)

// PreKeyBundle represents a user's published X3DH prekey material.
// Only public keys are stored — never private key material.
type PreKeyBundle struct {
	// IdentityKey is the user's long-term Curve25519 identity public key (base64url).
	IdentityKey string `json:"identity_key"`
	// Ed25519IdentityKey is the user's long-term Ed25519 identity public key
	// (base64url). Used by initiators to verify the signed prekey signature.
	// If empty, signature verification is skipped (dev/self-session mode).
	Ed25519IdentityKey string `json:"ed25519_identity_key,omitempty"`
	// SignedPreKeyID is the key ID of the signed prekey.
	SignedPreKeyID int `json:"signed_pre_key_id"`
	// SignedPreKey is the user's signed Curve25519 prekey public key (base64url).
	SignedPreKey string `json:"signed_pre_key"`
	// SignedPreKeySignature is the Ed25519 signature over (key_id || signed_pre_key) (base64url).
	SignedPreKeySignature string `json:"signed_pre_key_signature"`
	// OneTimePreKeys is a list of one-time prekey public keys (base64url).
	// Each entry is {"key_id": int, "public_key": string}.
	OneTimePreKeys []OneTimePreKeyEntry `json:"one_time_pre_keys,omitempty"`
}

// OneTimePreKeyEntry is a single one-time prekey in the published bundle.
type OneTimePreKeyEntry struct {
	KeyID     int    `json:"key_id"`
	PublicKey string `json:"public_key"` // base64url-encoded Curve25519 public key
}

// PreKeyStore persists prekey bundles per blind_hash_id.
type PreKeyStore interface {
	// Publish stores (or replaces) the prekey bundle for [blindHashID].
	// The bundle must carry only public key material.
	Publish(ctx context.Context, blindHashID string, bundle PreKeyBundle) error
	// Get returns the prekey bundle for [blindHashID], or nil if none exists.
	Get(ctx context.Context, blindHashID string) (*PreKeyBundle, error)
	// ConsumeOneTimePreKey removes and returns one one-time prekey for
	// [blindHashID] (used by the initiator during X3DH). Returns nil if
	// no one-time prekeys are available.
	ConsumeOneTimePreKey(ctx context.Context, blindHashID string) (*OneTimePreKeyEntry, error)
	// CountOneTimePreKeys returns the number of remaining one-time prekeys
	// for [blindHashID]. Used by the client to decide when to replenish.
	CountOneTimePreKeys(ctx context.Context, blindHashID string) (int, error)
}

// ---------------------------------------------------------------------------
// Validation helpers
// ---------------------------------------------------------------------------

// validBase64Key checks that [encoded] is a valid base64url-encoded string
// of the expected byte length.
func validBase64Key(encoded string, expectedLen int) bool {
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
	return len(raw) == expectedLen
}

// ValidatePreKeyBundle checks that a published bundle carries valid public key
// material. Returns an error describing the first validation failure.
func ValidatePreKeyBundle(b PreKeyBundle) error {
	if !validBase64Key(b.IdentityKey, curve25519PubKeyLen) {
		return errors.New("invalid identity key: must be base64url-encoded 32-byte Curve25519 public key")
	}
	// Ed25519 identity key is optional (dev/self-session may omit it),
	// but when present it must be a valid 32-byte key.
	if b.Ed25519IdentityKey != "" && !validBase64Key(b.Ed25519IdentityKey, ed25519PubKeyLen) {
		return errors.New("invalid ed25519 identity key: must be base64url-encoded 32-byte Ed25519 public key")
	}
	if !validBase64Key(b.SignedPreKey, curve25519PubKeyLen) {
		return errors.New("invalid signed prekey: must be base64url-encoded 32-byte Curve25519 public key")
	}
	if !validBase64Key(b.SignedPreKeySignature, ed25519SignatureLen) {
		return errors.New("invalid signed prekey signature: must be base64url-encoded 64-byte Ed25519 signature")
	}
	if len(b.OneTimePreKeys) > maxOneTimePreKeys {
		return errors.New("too many one-time prekeys")
	}
	for _, otpk := range b.OneTimePreKeys {
		if !validBase64Key(otpk.PublicKey, curve25519PubKeyLen) {
			return errors.New("invalid one-time prekey: must be base64url-encoded 32-byte Curve25519 public key")
		}
	}
	return nil
}

// ---------------------------------------------------------------------------
// In-memory implementation (dev / tests)
// ---------------------------------------------------------------------------

// InMemoryPreKeyStore is a mutex-guarded in-memory PreKeyStore.
type InMemoryPreKeyStore struct {
	mu      sync.RWMutex
	bundles map[string]*PreKeyBundle // blind_hash_id → bundle
}

// NewInMemoryPreKeyStore returns an empty store.
func NewInMemoryPreKeyStore() *InMemoryPreKeyStore {
	return &InMemoryPreKeyStore{bundles: make(map[string]*PreKeyBundle)}
}

// Publish implements PreKeyStore.
func (s *InMemoryPreKeyStore) Publish(_ context.Context, blindHashID string, bundle PreKeyBundle) error {
	s.mu.Lock()
	defer s.mu.Unlock()
	// Store a copy to prevent mutation.
	cp := bundle
	if bundle.OneTimePreKeys != nil {
		cp.OneTimePreKeys = make([]OneTimePreKeyEntry, len(bundle.OneTimePreKeys))
		copy(cp.OneTimePreKeys, bundle.OneTimePreKeys)
	}
	s.bundles[blindHashID] = &cp
	return nil
}

// Get implements PreKeyStore.
func (s *InMemoryPreKeyStore) Get(_ context.Context, blindHashID string) (*PreKeyBundle, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	b, ok := s.bundles[blindHashID]
	if !ok {
		return nil, nil
	}
	// Return a copy.
	cp := *b
	if b.OneTimePreKeys != nil {
		cp.OneTimePreKeys = make([]OneTimePreKeyEntry, len(b.OneTimePreKeys))
		copy(cp.OneTimePreKeys, b.OneTimePreKeys)
	}
	return &cp, nil
}

// ConsumeOneTimePreKey implements PreKeyStore.
func (s *InMemoryPreKeyStore) ConsumeOneTimePreKey(_ context.Context, blindHashID string) (*OneTimePreKeyEntry, error) {
	s.mu.Lock()
	defer s.mu.Unlock()
	b, ok := s.bundles[blindHashID]
	if !ok || len(b.OneTimePreKeys) == 0 {
		return nil, nil
	}
	// Pop the first one-time prekey.
	entry := b.OneTimePreKeys[0]
	b.OneTimePreKeys = b.OneTimePreKeys[1:]
	return &entry, nil
}

// CountOneTimePreKeys implements PreKeyStore.
func (s *InMemoryPreKeyStore) CountOneTimePreKeys(_ context.Context, blindHashID string) (int, error) {
	s.mu.RLock()
	defer s.mu.RUnlock()
	b, ok := s.bundles[blindHashID]
	if !ok {
		return 0, nil
	}
	return len(b.OneTimePreKeys), nil
}
