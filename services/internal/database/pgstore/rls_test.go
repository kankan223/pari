package pgstore

import (
	"context"
	"strings"
	"testing"
	"time"

	"github.com/kankan223/pari/services/internal/identity"
	"github.com/kankan223/pari/services/internal/relay"
)

// TestRLSOutOfScopeDenied is the Task 4.5 RLS verification:
//
//  1. A role outside the civic_app policy sees ZERO rows in every table even
//     with full table grants (RLS, not GRANTs, is the barrier).
//  2. That role cannot write either (no WITH CHECK policy applies).
//  3. FORCE ROW LEVEL SECURITY subjects a non-superuser table owner to the
//     same policies — the owner sees nothing without a matching policy.
//  4. Only civic_app (the service role with the app_full_access policy) can
//     see the data.
func TestRLSOutOfScopeDenied(t *testing.T) {
	requireLive(t)
	ctx := context.Background()

	// --- Seed one row in every table as the application role. --------------
	const hash = "7777777777777777777777777777777777777777777777777777777777777777"
	if err := pg.Users().Create(ctx, identity.User{BlindHashID: hash, CreatedAt: time.Now().UTC()}); err != nil {
		t.Fatalf("seed user: %v", err)
	}
	if err := pg.Usernames().Claim(ctx, "rls_seed_user", hash, time.Now().UTC(), 30*24*time.Hour); err != nil {
		t.Fatalf("seed username: %v", err)
	}
	if err := pg.Devices().Register(ctx, hash, identity.Device{DeviceID: "rls-dev", PublicKey: rawBase64URL(make([]byte, 32))}); err != nil {
		t.Fatalf("seed device: %v", err)
	}
	now := time.Now().UTC()
	if err := pg.Requests().Create(ctx, relay.ConnectionRequest{
		ID:            "cafecafecafecafecafecafecafecafe",
		InitiatorHash: hash,
		TargetHash:    strings.Repeat("8", 64),
		Status:        relay.RequestPending,
		CreatedAt:     now,
		UpdatedAt:     now,
		ExpiresAt:     now.Add(30 * 24 * time.Hour),
	}); err != nil {
		t.Fatalf("seed connection request: %v", err)
	}
	if _, err := pg.db.ExecContext(ctx,
		`INSERT INTO refresh_tokens (token_hash, blind_hash_id, family_id, expires_at)
		 VALUES ('aabbccddeeff00112233445566778899', $1, 'rls-family', now() + interval '30 days')`,
		hash); err != nil {
		t.Fatalf("seed refresh token: %v", err)
	}

	tables := []string{"users", "usernames", "devices", "refresh_tokens", "connection_requests"}

	// --- 1. Outsider with grants: RLS hides every row. ----------------------
	for _, table := range tables {
		n := countAsRole(t, ctx, outsiderRole, "SELECT count(*) FROM "+table)
		if n != 0 {
			t.Errorf("outsider SELECT count(%s) = %d, want 0 (RLS must hide all rows)", table, n)
		}
	}

	// --- 2. Outsider write is rejected (no WITH CHECK policy). --------------
	tx, err := adminDB.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := tx.ExecContext(ctx, "SET LOCAL ROLE "+outsiderRole); err != nil {
		t.Fatal(err)
	}
	_, err = tx.ExecContext(ctx,
		"INSERT INTO users (blind_hash_id) VALUES ('8888888888888888888888888888888888888888888888888888888888888888')")
	_ = tx.Rollback()
	if err == nil {
		t.Error("outsider INSERT succeeded — RLS WITH CHECK must reject out-of-scope writes")
	}

	// --- 3. FORCE RLS: a non-superuser OWNER also sees zero rows. -----------
	// Tables are owned by the (superuser) migration role; superusers bypass
	// RLS, so hand ownership of `users` to a dedicated non-superuser role to
	// prove FORCE applies to the owner too. Restored afterwards.
	if _, err := adminDB.ExecContext(ctx, "ALTER TABLE users OWNER TO "+ownerRole); err != nil {
		t.Fatalf("alter owner: %v", err)
	}
	t.Cleanup(func() {
		_, _ = adminDB.ExecContext(context.Background(), "ALTER TABLE users OWNER TO postgres")
	})
	if n := countAsRole(t, ctx, ownerRole, "SELECT count(*) FROM users"); n != 0 {
		t.Errorf("owner (FORCE RLS, no policy) sees %d rows, want 0", n)
	}

	// --- 4. civic_app sees its data. ----------------------------------------
	for _, table := range tables {
		n := countAsApp(t, ctx, "SELECT count(*) FROM "+table)
		if n < 1 {
			t.Errorf("civic_app count(%s) = %d, want >= 1", table, n)
		}
	}
}

// countAsRole runs [query] as [role] inside a transaction-scoped SET LOCAL
// ROLE and returns the single integer result.
func countAsRole(t *testing.T, ctx context.Context, role, query string) int {
	t.Helper()
	tx, err := adminDB.BeginTx(ctx, nil)
	if err != nil {
		t.Fatal(err)
	}
	defer tx.Rollback() //nolint:errcheck
	if _, err := tx.ExecContext(ctx, "SET LOCAL ROLE "+role); err != nil {
		t.Fatalf("SET LOCAL ROLE %s: %v", role, err)
	}
	var n int
	if err := tx.QueryRowContext(ctx, query).Scan(&n); err != nil {
		t.Fatalf("query as %s: %v", role, err)
	}
	return n
}

// countAsApp runs [query] as the civic_app connection.
func countAsApp(t *testing.T, ctx context.Context, query string) int {
	t.Helper()
	var n int
	if err := pg.db.QueryRowContext(ctx, query).Scan(&n); err != nil {
		t.Fatalf("query as civic_app: %v", err)
	}
	return n
}

// TestRLSPoliciesExistLive confirms every table carries exactly one policy
// (defense-in-depth alongside the behavioral test).
func TestRLSPoliciesExistLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()

	rows, err := adminDB.QueryContext(ctx, `
		SELECT c.relname, count(p.polname)
		FROM pg_class c
		JOIN pg_policy p ON p.polrelid = c.oid
		WHERE c.relname IN ('users','usernames','devices','refresh_tokens','connection_requests')
		GROUP BY c.relname ORDER BY c.relname`)
	if err != nil {
		t.Fatalf("policies: %v", err)
	}
	defer rows.Close() //nolint:errcheck
	count := 0
	for rows.Next() {
		var table string
		var n int
		if err := rows.Scan(&table, &n); err != nil {
			t.Fatal(err)
		}
		count++
		if n != 1 {
			t.Errorf("table %s has %d policies, want 1", table, n)
		}
	}
	if count != 5 {
		t.Errorf("policies found on %d tables, want 5", count)
	}
}

// TestRLSPgcryptoAtRestLive backs the security checkpoint: pgcrypto is
// installed and symmetric encryption actually transforms plaintext.
func TestRLSPgcryptoAtRestLive(t *testing.T) {
	requireLive(t)
	ctx := context.Background()

	var present bool
	if err := adminDB.QueryRowContext(ctx,
		`SELECT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pgcrypto')`).Scan(&present); err != nil {
		t.Fatal(err)
	}
	if !present {
		t.Fatal("pgcrypto extension missing — PII encryption at rest unavailable")
	}

	var enc string
	if err := adminDB.QueryRowContext(ctx,
		`SELECT encode(pgp_sym_encrypt('secret-value', 'k'), 'hex')`).Scan(&enc); err != nil {
		t.Fatalf("pgp_sym_encrypt: %v", err)
	}
	if enc == "" || strings.Contains(enc, "secret-value") {
		t.Errorf("pgp_sym_encrypt output suspicious: %q", enc)
	}
}
