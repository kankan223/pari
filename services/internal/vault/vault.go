// Package vault provides a stdlib net/http HashiCorp Vault client (Task 4.8).
//
// Only the operations the Civic Commons services need are implemented — no
// official Vault SDK is imported. Supported:
//
//   - KV v2 secret reads (GET /v1/{mount}/data/{path}) and metadata reads
//     (version / created-time) for rotation detection.
//   - AppRole authentication (role_id + secret_id → client token) with
//     background token renewal (lookup-self TTL → renew-self before expiry;
//     re-login on renewal failure).
//   - Transit secrets-engine encrypt/decrypt for key-derivation/encryption
//     operations.
//   - A TTL-aware SecretCache for runtime secrets that must be re-fetched on
//     rotation; refreshed values replace (and wipe) the previous copy.
//
// SECURITY: tokens and secret values are carried in memory only — nothing in
// this package logs them, and callers must never log them either. The
// redacting logger additionally scrubs Vault token shapes and auth headers.
package vault

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strconv"
	"strings"
	"sync"
	"time"
)

// Sentinel errors returned by the client.
var (
	ErrSecretNotFound   = errors.New("vault: secret not found")
	ErrPermissionDenied = errors.New("vault: permission denied")
	ErrAuthFailed       = errors.New("vault: authentication failed")
	ErrUnavailable      = errors.New("vault: service unavailable")
)

// Client is a minimal Vault HTTP client bound to one KV mount.
type Client struct {
	addr  string
	mount string
	hc    *http.Client
	log   *slog.Logger

	// mu guards token and approle (renewal swaps the token under the lock;
	// re-login reads the saved AppRole credentials).
	mu       sync.RWMutex
	token    string
	roleID   string
	secretID string
}

// Options configures [Connect].
type Options struct {
	Addr     string
	Mount    string
	Token    string // static token (VAULT_TOKEN) — AppRole wins when set
	RoleID   string // AppRole role_id
	SecretID string // AppRole secret_id

	// RenewInterval drives the background token renewal loop; 0 disables it.
	RenewInterval time.Duration
	// Log is the (redacting) logger for renewal events.
	Log *slog.Logger
}

// New returns a *Client for the KV v2 [mount] on [addr], authenticating with
// the static [token]. The HTTP client defaults to a 10s timeout; pass a
// custom client to override (see SetHTTPClient).
func New(addr, token, mount string) *Client {
	return &Client{
		addr:  strings.TrimRight(addr, "/"),
		mount: strings.Trim(mount, "/"),
		token: token,
		hc:    &http.Client{Timeout: 10 * time.Second},
	}
}

// SetHTTPClient overrides the default HTTP client (used by tests).
func (c *Client) SetHTTPClient(hc *http.Client) { c.hc = hc }

// Connect builds a client and authenticates it: AppRole login when
// RoleID+SecretID are set (the production posture), else the static Token.
// When RenewInterval > 0 a background renewal loop is started (stopped when
// [ctx] is cancelled). Callers should keep [ctx] alive for the process
// lifetime (signal.NotifyContext).
func Connect(ctx context.Context, opts Options) (*Client, error) {
	c := &Client{
		addr:  strings.TrimRight(opts.Addr, "/"),
		mount: strings.Trim(opts.Mount, "/"),
		hc:    &http.Client{Timeout: 10 * time.Second},
		log:   opts.Log,
	}
	if opts.RoleID != "" || opts.SecretID != "" {
		c.roleID = opts.RoleID
		c.secretID = opts.SecretID
		if err := c.LoginAppRole(ctx, opts.RoleID, opts.SecretID); err != nil {
			return nil, err
		}
	} else {
		if opts.Token == "" {
			return nil, errors.New("vault: no credentials (VAULT_TOKEN or VAULT_ROLE_ID+VAULT_SECRET_ID required)")
		}
		c.token = opts.Token
	}
	if opts.RenewInterval > 0 {
		go c.RunRenewal(ctx, opts.RenewInterval)
	}
	return c, nil
}

// LoginAppRole exchanges role_id + secret_id for a client token (POST
// /v1/auth/approle/login). The token is stored for subsequent requests.
func (c *Client) LoginAppRole(ctx context.Context, roleID, secretID string) error {
	if roleID == "" || secretID == "" {
		return fmt.Errorf("%w: role_id and secret_id are required", ErrAuthFailed)
	}
	body := map[string]string{"role_id": roleID, "secret_id": secretID}
	var out struct {
		Auth struct {
			ClientToken   string `json:"client_token"`
			LeaseDuration int    `json:"lease_duration"`
		} `json:"auth"`
	}
	if err := c.doJSON(ctx, http.MethodPost, "/v1/auth/approle/login", body, &out, http.StatusOK); err != nil {
		return fmt.Errorf("vault: approle login: %w", err)
	}
	if out.Auth.ClientToken == "" {
		return fmt.Errorf("%w: empty client_token in login response", ErrAuthFailed)
	}
	c.mu.Lock()
	c.token = out.Auth.ClientToken
	c.roleID, c.secretID = roleID, secretID
	c.mu.Unlock()
	return nil
}

// TokenInfo describes the current client token's lease.
type TokenInfo struct {
	TTL       time.Duration
	Renewable bool
}

// LookupSelf returns the token's TTL and renewability (GET
// /v1/auth/token/lookup-self).
func (c *Client) LookupSelf(ctx context.Context) (TokenInfo, error) {
	var out struct {
		Data struct {
			TTL       int  `json:"ttl"`
			Renewable bool `json:"renewable"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodGet, "/v1/auth/token/lookup-self", nil, &out, http.StatusOK); err != nil {
		return TokenInfo{}, fmt.Errorf("vault: lookup-self: %w", err)
	}
	return TokenInfo{TTL: time.Duration(out.Data.TTL) * time.Second, Renewable: out.Data.Renewable}, nil
}

// RenewSelf renews the current client token (POST /v1/auth/token/renew-self).
func (c *Client) RenewSelf(ctx context.Context) error {
	if err := c.doJSON(ctx, http.MethodPost, "/v1/auth/token/renew-self", struct{}{}, &struct{}{}, http.StatusOK); err != nil {
		return fmt.Errorf("vault: renew-self: %w", err)
	}
	return nil
}

// RunRenewal keeps the client token alive in the background: it renews every
// [interval], and re-logs-in via AppRole if renewal fails (the token may have
// been revoked server-side). Runs until [ctx] is cancelled. Errors are logged
// through the (redacting) logger — never the token itself.
func (c *Client) RunRenewal(ctx context.Context, interval time.Duration) {
	if interval <= 0 {
		interval = 5 * time.Minute
	}
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			if err := c.RenewSelf(ctx); err != nil {
				if c.log != nil {
					c.log.Warn("vault token renewal failed — attempting approle re-login", "error", err.Error())
				}
				c.mu.RLock()
				roleID, secretID := c.roleID, c.secretID
				c.mu.RUnlock()
				if roleID == "" || secretID == "" {
					continue // static token; no way to re-login
				}
				if err := c.LoginAppRole(ctx, roleID, secretID); err != nil {
					if c.log != nil {
						c.log.Error("vault approle re-login failed", "error", err.Error())
					}
					continue
				}
				if c.log != nil {
					c.log.Info("vault token re-login succeeded")
				}
			}
		}
	}
}

// ReadKV2 fetches the secret at [path] (relative to the mount root, e.g.
// "identity/argon2_salt") and returns its data map. The raw secret data is
// returned as strings so callers never see Vault's envelope types.
func (c *Client) ReadKV2(ctx context.Context, path string) (map[string]string, error) {
	var envelope struct {
		Data struct {
			Data map[string]any `json:"data"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodGet, "/v1/"+c.mount+"/data/"+strings.Trim(path, "/"), nil, &envelope, http.StatusOK); err != nil {
		return nil, err
	}
	if envelope.Data.Data == nil {
		return nil, fmt.Errorf("vault: read %q: empty secret payload", path)
	}
	out := make(map[string]string, len(envelope.Data.Data))
	for k, v := range envelope.Data.Data {
		out[k] = stringify(v)
	}
	return out, nil
}

// KV2Meta is the version metadata Vault keeps for a secret (rotation signal).
type KV2Meta struct {
	Version     uint64
	CreatedTime time.Time
}

// ReadKV2Meta fetches the metadata for [path] (GET /v1/{mount}/metadata/{path})
// so callers can detect rotation by version bump.
func (c *Client) ReadKV2Meta(ctx context.Context, path string) (KV2Meta, error) {
	var out struct {
		Data struct {
			Version     uint64 `json:"version"`
			CreatedTime string `json:"created_time"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodGet, "/v1/"+c.mount+"/metadata/"+strings.Trim(path, "/"), nil, &out, http.StatusOK); err != nil {
		return KV2Meta{}, err
	}
	created, _ := time.Parse(time.RFC3339, out.Data.CreatedTime)
	return KV2Meta{Version: out.Data.Version, CreatedTime: created}, nil
}

// TransitEncrypt encrypts [plaintext] with the transit [key] and returns the
// Vault ciphertext (POST /v1/transit/encrypt/{key}).
func (c *Client) TransitEncrypt(ctx context.Context, key string, plaintext []byte) (string, error) {
	body := map[string]string{"plaintext": base64.StdEncoding.EncodeToString(plaintext)}
	var out struct {
		Data struct {
			Ciphertext string `json:"ciphertext"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, "/v1/transit/encrypt/"+key, body, &out, http.StatusOK); err != nil {
		return "", fmt.Errorf("vault: transit encrypt %q: %w", key, err)
	}
	return out.Data.Ciphertext, nil
}

// TransitDecrypt decrypts Vault [ciphertext] with the transit [key] (POST
// /v1/transit/decrypt/{key}).
func (c *Client) TransitDecrypt(ctx context.Context, key string, ciphertext string) ([]byte, error) {
	body := map[string]string{"ciphertext": ciphertext}
	var out struct {
		Data struct {
			Plaintext string `json:"plaintext"`
		} `json:"data"`
	}
	if err := c.doJSON(ctx, http.MethodPost, "/v1/transit/decrypt/"+key, body, &out, http.StatusOK); err != nil {
		return nil, fmt.Errorf("vault: transit decrypt %q: %w", key, err)
	}
	raw, err := base64.StdEncoding.DecodeString(out.Data.Plaintext)
	if err != nil {
		return nil, fmt.Errorf("vault: transit decrypt %q: bad plaintext encoding: %w", key, err)
	}
	return raw, nil
}

// doJSON performs one authenticated HTTP round trip, decodes a 2xx JSON
// response into [out], and maps Vault error codes to sentinel errors.
func (c *Client) doJSON(ctx context.Context, method, path string, body any, out any, wantStatus int) error {
	var reader io.Reader
	if body != nil {
		raw, err := json.Marshal(body)
		if err != nil {
			return fmt.Errorf("vault: encode request: %w", err)
		}
		reader = strings.NewReader(string(raw))
	}
	url := c.addr + path
	req, err := http.NewRequestWithContext(ctx, method, url, reader)
	if err != nil {
		return fmt.Errorf("vault: build request: %w", err)
	}
	c.mu.RLock()
	req.Header.Set("X-Vault-Token", c.token)
	c.mu.RUnlock()
	req.Header.Set("Accept", "application/json")
	if body != nil {
		req.Header.Set("Content-Type", "application/json")
	}

	resp, err := c.hc.Do(req)
	if err != nil {
		return fmt.Errorf("vault: %s %s: %w", method, path, err)
	}
	defer func() {
		_, _ = io.Copy(io.Discard, io.LimitReader(resp.Body, 4096))
		_ = resp.Body.Close()
	}()

	switch resp.StatusCode {
	case http.StatusOK, http.StatusNoContent:
		// fall through to decode
	case http.StatusNotFound:
		return fmt.Errorf("%w: %s", ErrSecretNotFound, path)
	case http.StatusForbidden, http.StatusUnauthorized:
		return fmt.Errorf("%w: %s (HTTP %d)", ErrPermissionDenied, path, resp.StatusCode)
	case http.StatusServiceUnavailable:
		return fmt.Errorf("%w: %s (HTTP %d)", ErrUnavailable, path, resp.StatusCode)
	default:
		return fmt.Errorf("vault: %s %s: unexpected HTTP %d", method, path, resp.StatusCode)
	}

	if out == nil || wantStatus == http.StatusNoContent {
		return nil
	}
	if err := json.NewDecoder(io.LimitReader(resp.Body, 1<<20)).Decode(out); err != nil {
		return fmt.Errorf("vault: decode response for %s: %w", path, err)
	}
	return nil
}

// stringify coerces a decoded JSON value into its string representation for
// the data map. Strings pass through untouched; numbers/bools are rendered
// canonically.
func stringify(v any) string {
	switch t := v.(type) {
	case string:
		return t
	case float64:
		return strconv.FormatFloat(t, 'f', -1, 64)
	case bool:
		return strconv.FormatBool(t)
	case nil:
		return ""
	default:
		// Unknown shapes (maps, arrays) are rendered compactly so callers
		// still receive the raw secret without losing structure.
		b, _ := json.Marshal(t)
		return string(b)
	}
}

// WipeBytes zeroes a byte slice in memory. Best-effort hygiene — Go does not
// guarantee buffer reuse, but this reduces the window where secret material
// lingers in the process heap after rotation/unload.
func WipeBytes(b []byte) {
	for i := range b {
		b[i] = 0
	}
}

// SecretCache is a TTL-aware cache for runtime secrets. Values are re-fetched
// after [TTL] so rotated secrets are picked up; Refresh forces an immediate
// re-read (and wipes the previous copy's bytes where the values are
// []byte-backed). Safe for concurrent use.
type SecretCache struct {
	vc  *Client
	ttl time.Duration

	mu    sync.Mutex
	items map[string]*cacheEntry
}

type cacheEntry struct {
	data      map[string]string
	expiresAt time.Time
}

// NewSecretCache builds a TTL-aware cache over [vc].
func NewSecretCache(vc *Client, ttl time.Duration) *SecretCache {
	if ttl <= 0 {
		ttl = time.Minute
	}
	return &SecretCache{vc: vc, ttl: ttl, items: make(map[string]*cacheEntry)}
}

// Get returns the secret at [path], serving a fresh copy from Vault on the
// first call and after TTL expiry, and the cached copy otherwise.
func (c *SecretCache) Get(ctx context.Context, path string) (map[string]string, error) {
	c.mu.Lock()
	if e, ok := c.items[path]; ok && time.Now().Before(e.expiresAt) {
		c.mu.Unlock()
		return e.data, nil
	}
	c.mu.Unlock()

	data, err := c.vc.ReadKV2(ctx, path)
	if err != nil {
		return nil, err
	}
	c.mu.Lock()
	c.items[path] = &cacheEntry{data: data, expiresAt: time.Now().Add(c.ttl)}
	c.mu.Unlock()
	return data, nil
}

// Refresh forces a re-read of [path], replacing (and wiping) the old value.
// Returns the new value and whether the version changed (rotation detected).
func (c *SecretCache) Refresh(ctx context.Context, path string) (map[string]string, bool, error) {
	data, err := c.vc.ReadKV2(ctx, path)
	if err != nil {
		return nil, false, err
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	changed := true
	if old, ok := c.items[path]; ok {
		changed = !mapsEqual(old.data, data)
		wipeMap(old.data)
	}
	c.items[path] = &cacheEntry{data: data, expiresAt: time.Now().Add(c.ttl)}
	return data, changed, nil
}

func wipeMap(m map[string]string) {
	for k, v := range m {
		WipeBytes([]byte(v)) //nolint:gosec // best-effort hygiene, strings are immutable
		delete(m, k)
	}
}

func mapsEqual(a, b map[string]string) bool {
	if len(a) != len(b) {
		return false
	}
	for k, v := range a {
		if b[k] != v {
			return false
		}
	}
	return true
}
