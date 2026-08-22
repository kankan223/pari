package identity

import (
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"strings"
	"time"
)

// API route paths (mounted under /v1/identity by the service binary).
const (
	routeOTPRequest     = "POST /v1/identity/otp/request"
	routeOTPVerify      = "POST /v1/identity/otp/verify"
	routeUsername       = "POST /v1/identity/username/claim"
	routeUsernameRel    = "POST /v1/identity/username/release"
	routeUsernameLookup = "GET /v1/identity/username/{username}"
	routeDevices        = "POST /v1/identity/devices"
	routeDevicesList    = "GET /v1/identity/devices"
	routeDevicesDel     = "DELETE /v1/identity/devices/{device_id}"
	// #nosec G101 -- route path, not a credential.
	routeTokenRefresh = "POST /v1/identity/token/refresh"
	// #nosec G101 -- route path, not a credential.
	routeTokenRevoke = "POST /v1/identity/token/revoke"
	routeMe          = "GET /v1/identity/me"
	routePreKeyPublish = "POST /v1/identity/prekeys"
	routePreKeyFetch   = "GET /v1/identity/prekeys/{blind_hash_id}"
	routeHealth = "GET /health"
)

// maxBodyBytes bounds request bodies (1 MiB).
const maxBodyBytes = 1 << 20

// Server is the identity service HTTP API.
type Server struct {
	svc *Service
	log *slog.Logger
	mux *http.ServeMux
}

// NewServer wires the routes onto a Go 1.22 method-aware ServeMux.
func NewServer(svc *Service, log *slog.Logger) *Server {
	s := &Server{svc: svc, log: log, mux: http.NewServeMux()}

	s.mux.HandleFunc(routeOTPRequest, s.handleOTPRequest)
	s.mux.HandleFunc(routeOTPVerify, s.handleOTPVerify)
	s.mux.HandleFunc(routeUsername, s.requireAuth(s.handleUsernameClaim))
	s.mux.HandleFunc(routeUsernameRel, s.requireAuth(s.handleUsernameRelease))
	s.mux.HandleFunc(routeUsernameLookup, s.requireAuth(s.handleUsernameLookup))
	s.mux.HandleFunc(routeDevices, s.requireAuth(s.handleDeviceRegister))
	s.mux.HandleFunc(routeDevicesList, s.requireAuth(s.handleDeviceList))
	s.mux.HandleFunc(routeDevicesDel, s.requireAuth(s.handleDeviceRevoke))
	s.mux.HandleFunc(routeTokenRefresh, s.handleTokenRefresh)
	s.mux.HandleFunc(routeTokenRevoke, s.handleTokenRevoke)
	s.mux.HandleFunc(routeMe, s.requireAuth(s.handleMe))
	s.mux.HandleFunc(routePreKeyPublish, s.requireAuth(s.handlePreKeyPublish))
	s.mux.HandleFunc(routePreKeyFetch, s.requireAuth(s.handlePreKeyFetch))
	s.mux.HandleFunc(routeHealth, s.handleHealth)

	return s
}

// Handler returns the full middleware-wrapped handler.
func (s *Server) Handler() http.Handler {
	return s.securityHeaders(s.requestLog(s.recoverPanic(s.mux)))
}

// ---------------------------------------------------------------------------
// Middleware

// recoverPanic converts handler panics into 500s (and logs them).
func (s *Server) recoverPanic(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		defer func() {
			if rec := recover(); rec != nil {
				s.log.Error("panic", "path", r.URL.Path, "panic", "recovered")
				writeError(w, http.StatusInternalServerError, "internal_error", "internal error")
			}
		}()
		next.ServeHTTP(w, r)
	})
}

// statusRecorder captures the response status for request logging.
type statusRecorder struct {
	http.ResponseWriter
	status int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.status = code
	r.ResponseWriter.WriteHeader(code)
}

// requestLog emits one structured line per request — method, path, status,
// duration. It NEVER logs request bodies, headers, or the Authorization
// header (mirrors the gateway's PII-scrubbed access logging).
func (s *Server) requestLog(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		rec := &statusRecorder{ResponseWriter: w, status: http.StatusOK}
		next.ServeHTTP(rec, r)
		s.log.Info("http_request",
			"method", r.Method,
			"path", r.URL.Path,
			"status", rec.status,
			"duration_ms", time.Since(start).Milliseconds(),
		)
	})
}

// securityHeaders sets hardening headers and strips any accidental Server
// header.
func (s *Server) securityHeaders(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		h := w.Header()
		h.Set("X-Content-Type-Options", "nosniff")
		h.Set("Cache-Control", "no-store")
		next.ServeHTTP(w, r)
	})
}

// requireAuth verifies the Bearer access token and attaches the blind_hash_id
// subject to the request context.
func (s *Server) requireAuth(next http.HandlerFunc) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		token, err := bearerToken(r)
		if err != nil || token == "" {
			writeError(w, http.StatusUnauthorized, "unauthorized", "authentication required")
			return
		}
		subject, err := s.svc.VerifyAccessToken(r.Context(), token)
		if err != nil {
			writeError(w, http.StatusUnauthorized, "unauthorized", "token rejected")
			return
		}
		ctx := withBlindHashID(r.Context(), subject)
		next(w, r.WithContext(ctx))
	}
}

// bearerToken extracts the token from the Authorization header.
func bearerToken(r *http.Request) (string, error) {
	parts := strings.Fields(r.Header.Get("Authorization"))
	if len(parts) != 2 || !strings.EqualFold(parts[0], "bearer") {
		return "", errors.New("missing bearer token")
	}
	return parts[1], nil
}

// ---------------------------------------------------------------------------
// Request/response helpers

type errorBody struct {
	Error errorDetail `json:"error"`
}

type errorDetail struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

// writeError emits a generic JSON error envelope. Messages are deliberately
// generic — they never leak whether a phone/identity is registered.
func writeError(w http.ResponseWriter, status int, code, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(errorBody{Error: errorDetail{Code: code, Message: message}})
}

// writeJSON encodes [v] with a 200/201 status.
func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(v)
}

// decodeJSON reads a bounded request body into [dst].
func decodeJSON(w http.ResponseWriter, r *http.Request, dst any) bool {
	r.Body = http.MaxBytesReader(w, r.Body, maxBodyBytes)
	dec := json.NewDecoder(r.Body)
	if err := dec.Decode(dst); err != nil {
		writeError(w, http.StatusBadRequest, "invalid_request", "malformed request body")
		return false
	}
	return true
}

// mapError converts a service error into an HTTP response.
func (s *Server) mapError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, ErrInvalidPhone), errors.Is(err, ErrInvalidBlindHash):
		writeError(w, http.StatusBadRequest, "invalid_request", "invalid request parameters")
	case errors.Is(err, ErrOtpProviderUnavail):
		writeError(w, http.StatusServiceUnavailable, "sms_unavailable", "sms provider unavailable")
	case errors.Is(err, ErrOtpCodeMismatch), errors.Is(err, ErrOtpMissing):
		writeError(w, http.StatusUnauthorized, "invalid_otp", "invalid or expired otp")
	case errors.Is(err, ErrOtpAttempts):
		writeError(w, http.StatusTooManyRequests, "too_many_attempts", "too many attempts")
	case errors.Is(err, ErrUsernameClaim):
		writeError(w, http.StatusConflict, "username_unavailable", "username unavailable")
	case errors.Is(err, ErrUsernameRelease):
		writeError(w, http.StatusConflict, "username_not_owned", "username not owned")
	case errors.Is(err, ErrUsernameNotFound):
		writeError(w, http.StatusNotFound, "not_found", "username not found")
	case errors.Is(err, ErrDeviceKey):
		writeError(w, http.StatusBadRequest, "invalid_public_key", "invalid device public key")
	case errors.Is(err, ErrDeviceCap):
		writeError(w, http.StatusConflict, "device_limit", "device limit reached")
	case errors.Is(err, ErrAuthRequired), errors.Is(err, ErrTokenUnauthorized):
		writeError(w, http.StatusUnauthorized, "unauthorized", "token rejected")
	case errors.Is(err, ErrUserNotFound):
		writeError(w, http.StatusNotFound, "not_found", "identity not found")
	case errors.Is(err, ErrInvalidPreKeyBundle):
		writeError(w, http.StatusBadRequest, "invalid_request", "invalid prekey bundle")
	case errors.Is(err, ErrPreKeyUnavailable):
		writeError(w, http.StatusInternalServerError, "internal_error", "prekey store unavailable")
	default:
		s.log.Error("internal_error", "err", err.Error())
		writeError(w, http.StatusInternalServerError, "internal_error", "internal error")
	}
}

// ---------------------------------------------------------------------------
// Health handler

func (s *Server) handleHealth(w http.ResponseWriter, _ *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(map[string]string{"status": "ok"})
}

// ---------------------------------------------------------------------------
// Handlers

type otpRequestReq struct {
	Phone string `json:"phone"`
}

func (s *Server) handleOTPRequest(w http.ResponseWriter, r *http.Request) {
	var req otpRequestReq
	if !decodeJSON(w, r, &req) {
		return
	}
	result, err := s.svc.RequestOtp(r.Context(), req.Phone)
	if err != nil {
		s.mapError(w, err)
		return
	}
	resp := map[string]any{"requested": true, "blind_hash_id": result.BlindHashID}
	// Dev-only: include the OTP code in the response so the frontend can
	// display it during staging/testing. Empty string in production.
	if result.DevOTPCode != "" {
		resp["dev_otp_code"] = result.DevOTPCode
	}
	writeJSON(w, http.StatusOK, resp)
}

type otpVerifyReq struct {
	BlindHashID string `json:"blind_hash_id"`
	OTP         string `json:"otp"`
}

func (s *Server) handleOTPVerify(w http.ResponseWriter, r *http.Request) {
	var req otpVerifyReq
	if !decodeJSON(w, r, &req) {
		return
	}
	result, err := s.svc.VerifyOtp(r.Context(), req.BlindHashID, req.OTP)
	if err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

type usernameReq struct {
	Username string `json:"username"`
}

func (s *Server) handleUsernameClaim(w http.ResponseWriter, r *http.Request) {
	var req usernameReq
	if !decodeJSON(w, r, &req) {
		return
	}
	hashID := mustSubject(r.Context())
	if err := s.svc.ClaimUsername(r.Context(), hashID, req.Username); err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"claimed": true, "username": req.Username})
}

func (s *Server) handleUsernameRelease(w http.ResponseWriter, r *http.Request) {
	hashID := mustSubject(r.Context())
	if err := s.svc.ReleaseUsername(r.Context(), hashID); err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"released": true})
}

// handleUsernameLookup resolves a claimed username to its owner's blind hash
// (auth-required, so the API Gateway surface cannot be scraped anonymously).
func (s *Server) handleUsernameLookup(w http.ResponseWriter, r *http.Request) {
	username := r.PathValue("username")
	lookup, err := s.svc.LookupUsername(r.Context(), username)
	if err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, lookup)
}

type deviceReq struct {
	DeviceID  string `json:"device_id"`
	PublicKey string `json:"public_key"`
}

func (s *Server) handleDeviceRegister(w http.ResponseWriter, r *http.Request) {
	var req deviceReq
	if !decodeJSON(w, r, &req) {
		return
	}
	hashID := mustSubject(r.Context())
	if err := s.svc.RegisterDevice(r.Context(), hashID, req.DeviceID, req.PublicKey); err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusCreated, map[string]any{"registered": true, "device_id": req.DeviceID})
}

func (s *Server) handleDeviceList(w http.ResponseWriter, r *http.Request) {
	hashID := mustSubject(r.Context())
	devices, err := s.svc.ListDevices(r.Context(), hashID)
	if err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"devices": devices})
}

func (s *Server) handleDeviceRevoke(w http.ResponseWriter, r *http.Request) {
	hashID := mustSubject(r.Context())
	deviceID := r.PathValue("device_id")
	if err := s.svc.RevokeDevice(r.Context(), hashID, deviceID); err != nil {
		s.mapError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type tokenReq struct {
	RefreshToken string `json:"refresh_token"`
}

func (s *Server) handleTokenRefresh(w http.ResponseWriter, r *http.Request) {
	var req tokenReq
	if !decodeJSON(w, r, &req) {
		return
	}
	result, err := s.svc.Refresh(r.Context(), req.RefreshToken)
	if err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, result)
}

func (s *Server) handleTokenRevoke(w http.ResponseWriter, r *http.Request) {
	var req tokenReq
	if !decodeJSON(w, r, &req) {
		return
	}
	if err := s.svc.RevokeRefresh(r.Context(), req.RefreshToken); err != nil {
		s.mapError(w, err)
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *Server) handleMe(w http.ResponseWriter, r *http.Request) {
	hashID := mustSubject(r.Context())
	user, devices, err := s.svc.GetUser(r.Context(), hashID)
	if err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{
		"user":    user,
		"devices": devices,
	})
}

// ---------------------------------------------------------------------------
// Prekey bundle handlers (X3DH key exchange)

func (s *Server) handlePreKeyPublish(w http.ResponseWriter, r *http.Request) {
	var req PreKeyBundle
	if !decodeJSON(w, r, &req) {
		return
	}
	hashID := mustSubject(r.Context())
	if err := s.svc.PublishPreKeys(r.Context(), hashID, req); err != nil {
		s.mapError(w, err)
		return
	}
	writeJSON(w, http.StatusOK, map[string]any{"published": true})
}

func (s *Server) handlePreKeyFetch(w http.ResponseWriter, r *http.Request) {
	peerHash := r.PathValue("blind_hash_id")
	if !ValidBlindHashID(peerHash) {
		writeError(w, http.StatusBadRequest, "invalid_request", "invalid blind hash id")
		return
	}
	bundle, consumed, err := s.svc.FetchBundle(r.Context(), peerHash)
	if err != nil {
		s.mapError(w, err)
		return
	}
	if bundle == nil {
		writeError(w, http.StatusNotFound, "not_found", "no prekey bundle published")
		return
	}
	// Build the response: the bundle plus the consumed one-time prekey
	// (if any). The initiator MUST use the consumed OTPK for this session.
	resp := map[string]any{
		"identity_key":           bundle.IdentityKey,
		"signed_pre_key_id":      bundle.SignedPreKeyID,
		"signed_pre_key":         bundle.SignedPreKey,
		"signed_pre_key_signature": bundle.SignedPreKeySignature,
	}
	if bundle.Ed25519IdentityKey != "" {
		resp["ed25519_identity_key"] = bundle.Ed25519IdentityKey
	}
	if consumed != nil {
		resp["consumed_one_time_pre_key"] = map[string]any{
			"key_id":     consumed.KeyID,
			"public_key": consumed.PublicKey,
		}
	}
	writeJSON(w, http.StatusOK, resp)
}

// mustSubject returns the authenticated subject; handlers under requireAuth
// always have it.
func mustSubject(ctx context.Context) string {
	hashID, _ := blindHashIDFromContext(ctx)
	return hashID
}
