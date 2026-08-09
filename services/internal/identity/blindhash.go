package identity

import (
	"context"
	"encoding/hex"
	"fmt"
	"sync"

	"golang.org/x/crypto/argon2"

	"github.com/kankan223/pari/services/internal/vault"
)

// Params holds the Argon2id parameters for phone → blind_hash_id derivation
// (Task 4.3). These MUST match the client-side PhoneHasher (Task 2.4) exactly
// so the hash computed on-device equals the hash computed by the Identity
// Service:
//
//	memory 65536 KiB (64 MB), iterations 3, parallelism 4, output 32 bytes
//
// The RFC 9106 constant version 0x13 is implied by golang.org/x/crypto/argon2.
type Params struct {
	Memory      uint32 // KiB
	Iterations  uint32
	Parallelism uint8
	KeyLength   uint32 // bytes
}

// DefaultParams returns the production Argon2id parameters (64 MB / 3 / 4 / 32B),
// identical to the client's PhoneHasher configuration.
func DefaultParams() Params {
	return Params{Memory: 65536, Iterations: 3, Parallelism: 4, KeyLength: 32}
}

// TestParams returns memory-light parameters for unit tests only. Never use
// these in production paths.
func TestParams() Params {
	return Params{Memory: 32, Iterations: 3, Parallelism: 4, KeyLength: 32}
}

// HashPhone derives the 64-hex-char blind_hash_id for [phone] with the given
// [salt] (the raw UTF-8 bytes of the Vault salt string, exactly as the client
// does) using Argon2id. The salt MUST be a *secret* from HashiCorp Vault —
// it is what makes the mapping one-way and rainbow-table-resistant.
//
// SECURITY: the phone's UTF-8 byte buffer is zeroed before returning.
func (p Params) HashPhone(phone string, salt []byte) string {
	phoneBytes := []byte(phone)
	return p.hashPhoneBytes(phoneBytes, salt)
}

// hashPhoneBytes derives the blind_hash_id from [phone] bytes and wipes the
// caller's buffer before returning. This is the single enforcement point for
// the "phone in memory ≤ 500 ms" constraint.
func (p Params) hashPhoneBytes(phone, salt []byte) string {
	defer wipeBytes(phone)
	key := argon2.IDKey(phone, salt, p.Iterations, p.Memory, p.Parallelism, p.KeyLength)
	return hex.EncodeToString(key)
}

// wipeBytes zeroes a byte slice in memory. Best-effort hygiene — Go does not
// guarantee buffer reuse, but this reduces the window where the plaintext
// phone lingers in the process heap.
func wipeBytes(b []byte) {
	for i := range b {
		b[i] = 0
	}
}

// SaltProvider supplies the secret Argon2id salt. The salt is fetched from
// HashiCorp Vault once and sealed; it is never written to disk or logged.
type SaltProvider interface {
	// Salt returns the current salt bytes.
	Salt(ctx context.Context) ([]byte, error)
}

// VaultSaltProvider loads the Argon2id salt from a KV v2 Vault path on first
// use, then serves the sealed value. The fetched salt string's UTF-8 bytes
// are used verbatim (matching the client's PhoneHasher.hashPhoneNumber).
type VaultSaltProvider struct {
	vc   *vault.Client
	path string

	once sync.Once
	salt []byte
	err  error
}

// NewVaultSaltProvider builds a sealed salt provider backed by [vc].
func NewVaultSaltProvider(vc *vault.Client, path string) *VaultSaltProvider {
	return &VaultSaltProvider{vc: vc, path: path}
}

// Salt implements SaltProvider. The lookup happens exactly once; subsequent
// calls return the sealed value. Errors are sealed too, so a transient Vault
// outage fails fast once instead of retrying a broken config.
func (p *VaultSaltProvider) Salt(ctx context.Context) ([]byte, error) {
	p.once.Do(func() {
		secret, err := p.vc.ReadKV2(ctx, p.path)
		if err != nil {
			p.err = fmt.Errorf("fetch argon2 salt from vault: %w", err)
			return
		}
		raw, ok := secret["value"]
		if !ok || raw == "" {
			// Tolerate any key name; the canonical name is "value".
			for _, v := range secret {
				if v != "" {
					raw = v
					break
				}
			}
		}
		if raw == "" {
			p.err = fmt.Errorf("vault secret %q has no usable salt value", p.path)
			return
		}
		p.salt = []byte(raw)
	})
	if p.err != nil {
		return nil, p.err
	}
	return p.salt, nil
}

// StaticSaltProvider is a fixed salt for tests and non-production fallback.
type StaticSaltProvider struct {
	salt []byte
}

// NewStaticSaltProvider returns a provider serving [salt] bytes.
func NewStaticSaltProvider(salt []byte) *StaticSaltProvider {
	return &StaticSaltProvider{salt: salt}
}

// Salt implements SaltProvider.
func (p *StaticSaltProvider) Salt(context.Context) ([]byte, error) {
	return p.salt, nil
}
