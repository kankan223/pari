package idempotency

import (
	"encoding/json"
	"log/slog"
	"net/http"
	"time"

	"github.com/kankan223/pari/services/internal/cache"
)

// HeaderName is the HTTP header carrying the client's idempotency key
// (mirrors the Flutter client's IdempotencyKeyGenerator.headerName, Task 5.2).
const HeaderName = "Idempotency-Key"

// Middleware dedupes mutation requests by their Idempotency-Key (Task 5.3).
//
// Behaviour (standard REST idempotency semantics):
//   - no header            → non-idempotent passthrough (legacy/internal callers)
//   - malformed key        → 400 (not a UUID v4 — must never reach Redis)
//   - key in_progress      → 409 Conflict (a concurrent duplicate is running)
//   - key completed        → replay the cached status/body, handler NOT called
//   - key absent           → claim, run the handler, cache the 2xx response
//     (a failed handler clears the key so retries reprocess)
type Middleware struct {
	store Store
	ttl   time.Duration
	log   *slog.Logger
	// actorFrom extracts the authenticated actor (blind_hash_id) from the
	// request when scoping is enabled; nil disables actor scoping.
	actorFrom func(*http.Request) string
}

// NewMiddleware builds the dedup middleware over [store]. [ttl] is the
// dedup window (default 24h per Task 5.3; IDEMPOTENCY_TTL overrides it).
func NewMiddleware(store Store, ttl time.Duration, log *slog.Logger) *Middleware {
	if ttl <= 0 {
		ttl = 24 * time.Hour
	}
	if log == nil {
		log = slog.Default()
	}
	return &Middleware{store: store, ttl: ttl, log: log}
}

// ScopedBy namespaces dedup keys per authenticated actor: with [actorFrom]
// set, keys become `idempotency:{actor}:{uuid}` so one user replaying
// another user's UUID can never read a cached response they did not produce.
// The middleware is used INSIDE the auth chain, so [actorFrom] (e.g. the
// relay's hashFrom) always returns the verified subject for scoped routes.
func (m *Middleware) ScopedBy(actorFrom func(*http.Request) string) *Middleware {
	m.actorFrom = actorFrom
	return m
}

// Wrap returns [next] wrapped with idempotent dedup.
func (m *Middleware) Wrap(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		raw := r.Header.Get(HeaderName)
		if raw == "" {
			// No idempotency contract — pass through unchanged. Rejecting
			// here would break health probes / legacy callers.
			next(w, r)
			return
		}
		if !cache.ValidateIdempotencyKey(raw) {
			writeError(w, http.StatusBadRequest, "invalid Idempotency-Key: must be a UUID v4")
			return
		}
		var key string
		var err error
		if m.actorFrom != nil {
			// Actor-scoped (production): the key is namespaced per verified
			// subject. A request that somehow lacks a subject is a server
			// wiring error — fail closed rather than degrade to unscoped.
			actor := m.actorFrom(r)
			key, err = cache.IdempotencyKeyScoped(actor, raw)
		} else {
			key, err = cache.IdempotencyKey(raw)
		}
		if err != nil {
			// Unreachable for a valid UUID (and, when scoped, requires a
			// 64-hex actor). Fail closed — never fall through to Redis with
			// an unvalidated key.
			writeError(w, http.StatusBadRequest, "invalid Idempotency-Key")
			return
		}

		// --- First sight? Claim atomically. ---
		won, err := m.store.Claim(r.Context(), key, m.ttl)
		if err != nil {
			m.log.Error("idempotency claim failed", "error", err.Error())
			writeError(w, http.StatusInternalServerError, "internal error")
			return
		}

		if !won {
			// Key already exists: in_progress (concurrent duplicate) or
			// completed (a retry of a finished mutation).
			entry, ok, err := m.store.Get(r.Context(), key)
			if err != nil {
				m.log.Error("idempotency read failed", "error", err.Error())
				writeError(w, http.StatusInternalServerError, "internal error")
				return
			}
			if !ok {
				// Claim raced with a TTL expiry: treat as a duplicate.
				writeError(w, http.StatusConflict, "request already in progress")
				return
			}
			switch entry.Status {
			case StatusCompleted:
				// Signal to the client that this is a replay of a previously
				// processed mutation, not a fresh execution (Stripe-style).
				w.Header().Set("Idempotent-Replayed", "true")
				replay(w, entry)
			default:
				writeError(w, http.StatusConflict, "request already in progress")
			}
			return
		}

		// --- We won the claim: run the handler, capture its response. ---
		rec := &recorder{w: w, status: http.StatusOK}
		next(rec, r)

		if rec.status >= 200 && rec.status < 300 && !rec.overflow {
			// Cache only success responses for replay. A failed mutation
			// clears the key so the client's next retry reprocesses.
			if err := m.store.Complete(r.Context(), key, rec.status, rec.body, rec.contentType, m.ttl); err != nil {
				// The mutation already ran — a cache write failure must not
				// turn a success into an error (the client will retry and
				// may re-apply; better than a 500 on a committed mutation).
				m.log.Error("idempotency cache write failed", "error", err.Error())
			}
		} else {
			if err := m.store.Clear(r.Context(), key); err != nil {
				m.log.Error("idempotency clear failed", "error", err.Error())
			}
		}
	}
}

// replay writes the cached response without invoking the handler.
func replay(w http.ResponseWriter, e Entry) {
	if e.ContentType != "" {
		w.Header().Set("Content-Type", e.ContentType)
	}
	w.WriteHeader(e.StatusCode)
	_, _ = w.Write(e.Body)
}

// writeError writes a JSON error envelope (no PII), matching the relay's
// writeJSON convention.
func writeError(w http.ResponseWriter, status int, msg string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(map[string]string{"error": msg})
}

// recorder captures the handler's status, body and content type while
// streaming the response through to the client as normal.
type recorder struct {
	w           http.ResponseWriter
	status      int
	body        []byte
	contentType string
	overflow    bool // response exceeded the 64 KiB cache cap
}

func (r *recorder) Header() http.Header { return r.w.Header() }

func (r *recorder) WriteHeader(code int) {
	r.status = code
	r.w.WriteHeader(code)
}

func (r *recorder) Write(p []byte) (int, error) {
	if ct := r.w.Header().Get("Content-Type"); ct != "" && r.contentType == "" {
		r.contentType = ct
	}
	// Cap buffered responses so the cache never grows unbounded (relay
	// responses are small JSON objects; 64 KiB is far beyond any of them).
	// Once over the cap we stop buffering entirely — the client still gets
	// the full response, but it is not cached for replay.
	if len(r.body) < 64<<10 {
		room := 64<<10 - len(r.body)
		if len(p) <= room {
			r.body = append(r.body, p...)
		} else {
			r.body = append(r.body, p[:room]...)
			r.overflow = true
		}
	}
	return r.w.Write(p)
}
