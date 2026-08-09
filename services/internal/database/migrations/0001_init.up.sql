-- Civic Commons schema migration 0001 (Task 4.5: PostgreSQL Schema & Migrations).
--
-- Creates the core relational schema for the identity + relay services:
--   extensions   → postgis, pgcrypto, pg_stat_statements, uuid-ossp
--   tables       → users, usernames, devices, refresh_tokens, connection_requests
--   security     → Row-Level Security (FORCE) + per-table app policies,
--                  pgcrypto symmetric encryption for PII at rest
--
-- The migration is transactional: PostgreSQL executes the whole script inside
-- the runner's transaction, so a failure rolls everything back.

-- ---------------------------------------------------------------------------
-- Extensions (PostGIS for the geographic layer in Task 7; pgcrypto for
-- encryption at rest; pg_stat_statements for query observability; uuid-ossp
-- for UUID generation).
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements;
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ---------------------------------------------------------------------------
-- Roles. Created NOLOGIN so the schema is self-contained and secrets never
-- live in SQL files; the cluster bootstrap (cloud-init/ESO) activates them
-- with ALTER ROLE ... LOGIN PASSWORD (from Vault) after provisioning.
-- ---------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_app') THEN
        CREATE ROLE civic_app NOLOGIN;
    END IF;
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_replicator') THEN
        CREATE ROLE civic_replicator NOLOGIN REPLICATION;
    END IF;
END
$$;

-- ---------------------------------------------------------------------------
-- users — the minimum-claim identity record. The ONLY identifier is the
-- Argon2id blind_hash_id; raw phone numbers never reach the database.
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    blind_hash_id text        PRIMARY KEY,                -- 64-hex Argon2id blind hash
    username      text        UNIQUE,                     -- current display handle (nullable)
    created_at    timestamptz NOT NULL DEFAULT now(),
    updated_at    timestamptz NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------------
-- usernames — claim/release ledger with the 30-day cooldown. A row records
-- the current owner and, after release, when the cooldown window started.
-- ---------------------------------------------------------------------------
CREATE TABLE usernames (
    username    text        PRIMARY KEY,
    owner_hash  text        NOT NULL,                      -- blind_hash_id of the holder
    claimed_at  timestamptz NOT NULL,
    released_at timestamptz                                -- NULL while held / cooldown start
);

CREATE INDEX idx_usernames_owner ON usernames (owner_hash);

-- ---------------------------------------------------------------------------
-- devices — registered device public keys. public_key_enc holds the key
-- encrypted at rest with pgcrypto (pgp_sym_encrypt using the session GUC
-- civic.enc_key); the store layer decrypts on read. The ciphertext is
-- opaque to anything without the key.
-- ---------------------------------------------------------------------------
CREATE TABLE devices (
    blind_hash_id   text        NOT NULL REFERENCES users (blind_hash_id) ON DELETE CASCADE,
    device_id       text        NOT NULL,
    public_key_enc  bytea       NOT NULL,                  -- pgcrypto-encrypted Ed25519 public key
    registered_at   timestamptz NOT NULL DEFAULT now(),
    last_seen_at    timestamptz NOT NULL DEFAULT now(),
    PRIMARY KEY (blind_hash_id, device_id)
);

COMMENT ON COLUMN devices.public_key_enc IS
    'Ed25519 public key encrypted at rest with pgcrypto (pgp_sym_encrypt, civic.enc_key) — PII protection';

-- ---------------------------------------------------------------------------
-- refresh_tokens — durable session record. Active sessions live in Redis
-- (techstack §7.2); this table is the persistent audit/restart store. Only
-- SHA-256 hashes of tokens are persisted — never raw tokens.
-- ---------------------------------------------------------------------------
CREATE TABLE refresh_tokens (
    token_hash    text        PRIMARY KEY,                 -- SHA-256 hex of the raw token
    blind_hash_id text        NOT NULL REFERENCES users (blind_hash_id) ON DELETE CASCADE,
    family_id     text        NOT NULL,                    -- rotation family (reuse detection)
    expires_at    timestamptz NOT NULL,
    created_at    timestamptz NOT NULL DEFAULT now(),
    revoked_at    timestamptz                              -- NULL until revoked
);

CREATE INDEX idx_refresh_tokens_family ON refresh_tokens (family_id);
CREATE INDEX idx_refresh_tokens_user ON refresh_tokens (blind_hash_id);

-- ---------------------------------------------------------------------------
-- connection_requests — the relay's connect-request state machine
-- (pending → accepted | rejected | withdrawn | expired).
-- ---------------------------------------------------------------------------
CREATE TABLE connection_requests (
    id             text        PRIMARY KEY,                -- 32-hex random id
    initiator_hash text        NOT NULL,
    target_hash    text        NOT NULL,
    status         text        NOT NULL CHECK (status IN
                      ('pending', 'accepted', 'rejected', 'withdrawn', 'expired')),
    created_at     timestamptz NOT NULL,
    updated_at     timestamptz NOT NULL,
    expires_at     timestamptz NOT NULL
);

CREATE INDEX idx_connection_requests_initiator ON connection_requests (initiator_hash);
CREATE INDEX idx_connection_requests_target ON connection_requests (target_hash);
-- At most one pending request per (initiator, target) pair (request-spam guard,
-- mirrors the relay manager's idempotent Create).
CREATE UNIQUE INDEX one_pending_pair ON connection_requests (initiator_hash, target_hash)
    WHERE status = 'pending';

-- ---------------------------------------------------------------------------
-- Row-Level Security. Every table enables RLS and FORCES it, so even the
-- table owner is subject to policies — a query outside the service role's
-- scope returns zero rows. The civic_app policy is the only door in.
-- ---------------------------------------------------------------------------
ALTER TABLE users                ENABLE ROW LEVEL SECURITY;
ALTER TABLE usernames            ENABLE ROW LEVEL SECURITY;
ALTER TABLE devices              ENABLE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens       ENABLE ROW LEVEL SECURITY;
ALTER TABLE connection_requests  ENABLE ROW LEVEL SECURITY;

ALTER TABLE users                FORCE ROW LEVEL SECURITY;
ALTER TABLE usernames            FORCE ROW LEVEL SECURITY;
ALTER TABLE devices              FORCE ROW LEVEL SECURITY;
ALTER TABLE refresh_tokens       FORCE ROW LEVEL SECURITY;
ALTER TABLE connection_requests  FORCE ROW LEVEL SECURITY;

-- The single service role that may touch these tables.
CREATE POLICY app_full_access ON users               FOR ALL TO civic_app USING (true) WITH CHECK (true);
CREATE POLICY app_full_access ON usernames           FOR ALL TO civic_app USING (true) WITH CHECK (true);
CREATE POLICY app_full_access ON devices             FOR ALL TO civic_app USING (true) WITH CHECK (true);
CREATE POLICY app_full_access ON refresh_tokens      FOR ALL TO civic_app USING (true) WITH CHECK (true);
CREATE POLICY app_full_access ON connection_requests FOR ALL TO civic_app USING (true) WITH CHECK (true);

-- Application grants (RLS then filters by role; grants alone are insufficient).
GRANT SELECT, INSERT, UPDATE, DELETE ON users, usernames, devices, refresh_tokens, connection_requests TO civic_app;
