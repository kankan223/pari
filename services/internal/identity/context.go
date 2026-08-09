package identity

import "context"

// contextKey is an internal key type for request-scoped values (avoids
// collisions with other packages).
type contextKey string

const ctxKeyBlindHashID contextKey = "blind_hash_id"

// withBlindHashID attaches the authenticated subject to [ctx].
func withBlindHashID(ctx context.Context, hashID string) context.Context {
	return context.WithValue(ctx, ctxKeyBlindHashID, hashID)
}

// blindHashIDFromContext returns the authenticated subject, if any.
func blindHashIDFromContext(ctx context.Context) (string, bool) {
	v, ok := ctx.Value(ctxKeyBlindHashID).(string)
	return v, ok && v != ""
}
