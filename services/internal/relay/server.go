package relay

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"github.com/kankan223/pari/services/internal/idempotency"
)

// Server is the Messaging Relay Service HTTP surface: the WebSocket endpoint
// plus the connection-request REST API.
type Server struct {
	hub           *Hub
	authenticator Authenticator
	requests      *ConnectionRequestManager
	idem          *idempotency.Middleware
	log           *slog.Logger

	pingInterval time.Duration
	pongTimeout  time.Duration
	queueTTL     time.Duration
}

// ServerOptions configures the relay server.
type ServerOptions struct {
	Hub           *Hub
	Authenticator Authenticator
	Requests      *ConnectionRequestManager
	Logger        *slog.Logger
	PingInterval  time.Duration
	PongTimeout   time.Duration
	// QueueTTL is the offline-queue retention window; expired entries are
	// trimmed when a recipient's backlog is drained on reconnect.
	QueueTTL time.Duration
	// Idempotency, when set, dedupes the mutation endpoints by their
	// Idempotency-Key header (Task 5.3). Nil disables dedup (tests/legacy).
	Idempotency *idempotency.Middleware
}

// NewServer builds the relay HTTP/WS server.
func NewServer(opts ServerOptions) *Server {
	log := opts.Logger
	if log == nil {
		log = slog.Default()
	}
	idem := opts.Idempotency
	if idem != nil {
		// The middleware runs inside the auth chain, so hashFrom is always the
		// verified subject. Scoping the dedup key per actor prevents one user
		// from replaying another user's UUID to read a cached response.
		idem = idem.ScopedBy(hashFrom)
	}
	return &Server{
		hub:           opts.Hub,
		authenticator: opts.Authenticator,
		requests:      opts.Requests,
		idem:          idem,
		log:           log,
		pingInterval:  opts.PingInterval,
		pongTimeout:   opts.PongTimeout,
		queueTTL:      opts.QueueTTL,
	}
}

// Handler returns the routed HTTP handler.
func (s *Server) Handler() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("GET /v1/relay/ws", s.serveWS)
	mux.HandleFunc("GET /v1/relay/healthz", s.handleHealth)
	// The mutation endpoints are wrapped in the idempotency middleware INSIDE
	// auth: an unauthenticated request never consumes a dedup key, and the
	// middleware only caches the authenticated actor's own responses.
	mux.HandleFunc("POST /v1/relay/requests", s.auth(s.mutate(s.handleCreateRequest)))
	mux.HandleFunc("GET /v1/relay/requests", s.auth(s.handleListRequests))
	mux.HandleFunc("POST /v1/relay/requests/{id}/accept", s.auth(s.mutate(s.handleAcceptRequest)))
	mux.HandleFunc("POST /v1/relay/requests/{id}/reject", s.auth(s.mutate(s.handleRejectRequest)))
	mux.HandleFunc("POST /v1/relay/requests/{id}/withdraw", s.auth(s.mutate(s.handleWithdrawRequest)))
	return mux
}

// mutate wraps a mutation handler with idempotency dedup when configured.
func (s *Server) mutate(h http.HandlerFunc) http.HandlerFunc {
	if s.idem == nil {
		return h
	}
	return s.idem.Wrap(h)
}

// handleHealth is the liveness probe (no auth).
func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// ctxHashKey carries the authenticated blind_hash_id in the request context.
type ctxHashKey struct{}

// auth is the Bearer-token middleware: it verifies the access token with the
// Authenticator and stores the resulting blind_hash_id in the context.
func (s *Server) auth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, ok := bearerToken(r)
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		hash, err := s.authenticator.Authenticate(r.Context(), token)
		if err != nil {
			// Deliberately identical body for auth failures (no enumeration).
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "unauthorized"})
			return
		}
		ctx := context.WithValue(r.Context(), ctxHashKey{}, hash)
		next(w, r.WithContext(ctx))
	}
}

// bearerToken extracts the token from "Authorization: Bearer <token>".
func bearerToken(r *http.Request) (string, bool) {
	h := r.Header.Get("Authorization")
	const prefix = "Bearer "
	if !strings.HasPrefix(h, prefix) {
		return "", false
	}
	tok := strings.TrimSpace(strings.TrimPrefix(h, prefix))
	if tok == "" {
		return "", false
	}
	return tok, true
}

// hashFrom returns the authenticated blind_hash_id from the context.
func hashFrom(r *http.Request) string {
	h, _ := r.Context().Value(ctxHashKey{}).(string)
	return h
}

// --- connection request handlers -------------------------------------------

type createRequestReq struct {
	TargetHash string `json:"target_hash"`
}

func (s *Server) handleCreateRequest(w http.ResponseWriter, r *http.Request) {
	var body createRequestReq
	if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 4096)).Decode(&body); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid request body"})
		return
	}
	if body.TargetHash == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "target_hash is required"})
		return
	}
	req, err := s.requests.Create(r.Context(), hashFrom(r), body.TargetHash)
	if err != nil {
		// Create is idempotent while pending (returns the existing request),
		// so any error here is a genuine bad request.
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": err.Error()})
		return
	}
	writeJSON(w, http.StatusCreated, req)
}

func (s *Server) handleListRequests(w http.ResponseWriter, r *http.Request) {
	reqs, err := s.requests.ListFor(r.Context(), hashFrom(r))
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if reqs == nil {
		reqs = []ConnectionRequest{}
	}
	writeJSON(w, http.StatusOK, reqs)
}

func (s *Server) handleAcceptRequest(w http.ResponseWriter, r *http.Request) {
	s.handleRespond(w, r, func(id, actor string) (*ConnectionRequest, error) {
		return s.requests.Accept(r.Context(), id, actor)
	})
}

func (s *Server) handleRejectRequest(w http.ResponseWriter, r *http.Request) {
	s.handleRespond(w, r, func(id, actor string) (*ConnectionRequest, error) {
		return s.requests.Reject(r.Context(), id, actor)
	})
}

func (s *Server) handleWithdrawRequest(w http.ResponseWriter, r *http.Request) {
	s.handleRespond(w, r, func(id, actor string) (*ConnectionRequest, error) {
		return s.requests.Withdraw(r.Context(), id, actor)
	})
}

func (s *Server) handleRespond(w http.ResponseWriter, r *http.Request, fn func(id, actor string) (*ConnectionRequest, error)) {
	id := r.PathValue("id")
	if id == "" {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "request id required"})
		return
	}
	req, err := fn(id, hashFrom(r))
	switch {
	case errors.Is(err, ErrRequestNotFound):
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "request not found"})
	case errors.Is(err, ErrRequestForbidden):
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "forbidden"})
	case errors.Is(err, ErrRequestState):
		writeJSON(w, http.StatusConflict, map[string]string{"error": "request no longer pending"})
	case err != nil:
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
	default:
		writeJSON(w, http.StatusOK, req)
	}
}

// writeJSON writes a JSON response with a content-type guard.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}
