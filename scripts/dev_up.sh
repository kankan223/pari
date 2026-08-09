#!/usr/bin/env bash
# dev_up.sh — bring up the Civic Commons local development stack (Phase 4/5).
#
# The services need PostgreSQL, Redis and (optionally) NATS running locally.
# IMPORTANT: this machine already runs UNRELATED projects on 5432 (postgres),
# 6379 and 6380 (redis). This script deliberately uses the civic-dedicated
# ports so we never touch another project's data:
#   PostgreSQL  5433  (container: civic-postgres, postgis/postgis:16-3.4)
#   Redis       6381  (container: civic-redis,     redis:7-alpine)
#   NATS        4222  (container: civic-nats,      nats:2.10-alpine -js)
#
# It also activates the civic_app role (created NOLOGIN by migration 0001)
# with a dev password + schema USAGE, so services run AS civic_app and the
# Row-Level Security policies are actually enforced (a superuser would bypass
# them — defeating the Task 4.5 security checkpoint).
#
# Usage:
#   bash scripts/dev_up.sh          # start infra containers + role
#   bash scripts/dev_up.sh --env    # also print the runnable env (eval-able)
set -euo pipefail

# Anchor to the repo root so the script works from any working directory
# (not just <repo>): the migration file is referenced by absolute path below.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

PG_PORT=5433
REDIS_PORT=6381
NATS_PORT=4222
DEV_DB_PASSWORD="${CIVIC_DEV_DB_PASSWORD:-civic_app_dev}"

echo "==> Civic Commons local stack (ports ${PG_PORT}/${REDIS_PORT}/${NATS_PORT})"

# --- PostgreSQL (civic-dedicated: 5433) ------------------------------------
if ! docker ps --format '{{.Names}}' | grep -q '^civic-postgres$'; then
  echo "==> Starting civic-postgres on :${PG_PORT}"
  docker rm -f civic-postgres >/dev/null 2>&1 || true
  docker run -d --name civic-postgres \
    -p "${PG_PORT}:5432" \
    -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=postgres -e POSTGRES_DB=civic_commons \
    postgis/postgis:16-3.4 >/dev/null
  # Wait for readiness
  for i in $(seq 1 30); do
    if PGPASSWORD=postgres pg_isready -h localhost -p "${PG_PORT}" -U postgres >/dev/null 2>&1; then break; fi
    sleep 1
  done
else
  echo "==> civic-postgres already running on :${PG_PORT}"
fi

# --- Redis (civic-dedicated: 6381 — never reuse another project's 6379) ----
if ! docker ps --format '{{.Names}}' | grep -q '^civic-redis$'; then
  echo "==> Starting civic-redis on :${REDIS_PORT}"
  docker rm -f civic-redis >/dev/null 2>&1 || true
  docker run -d --name civic-redis -p "${REDIS_PORT}:6379" redis:7-alpine >/dev/null
else
  echo "==> civic-redis already running on :${REDIS_PORT}"
fi

# --- NATS (optional in dev — the relay falls back to a noop publisher) -----
if ! docker ps --format '{{.Names}}' | grep -q '^civic-nats$'; then
  echo "==> Starting civic-nats on :${NATS_PORT}"
  docker rm -f civic-nats >/dev/null 2>&1 || true
  docker run -d --name civic-nats -p "${NATS_PORT}:4222" nats:2.10-alpine -js >/dev/null
else
  echo "==> civic-nats already running on :${NATS_PORT}"
fi

# --- Bootstrap migrations as the superuser role (fresh DBs only) -----------
# Migration 0001 creates the postgis/pgcrypto/uuid-ossp extensions and the
# civic_app role — both need superuser privileges that the service role must
# never have. On a brand-new container the embedded runner (which the
# services execute as civic_app) would otherwise fail on CREATE EXTENSION.
# The runner is idempotent, so re-running is a no-op once applied.
# Capture to a variable first: under `set -o pipefail`, `grep -q` closing the
# pipe early would SIGPIPE psql and flip the branch (the exact failure class
# documented in verify_nats_live.sh). A missing schema_migrations table errors
# the query and yields empty output — which also means "bootstrap needed".
applied=$(PGPASSWORD=postgres psql -h localhost -p "${PG_PORT}" -U postgres -d civic_commons -tAc \
    "SELECT 1 FROM schema_migrations WHERE version = 1" 2>/dev/null || true)
if ! grep -q 1 <<<"${applied}"; then
  echo "==> Applying embedded migration 0001 as postgres (bootstrap role)"
  # psql -1 runs the whole input as one transaction: a failure rolls back the
  # DDL and the version record together, mirroring the Go runner. The runner
  # (services) will then see version 1 recorded and skip it on their startup.
  {
    cat "${REPO_ROOT}/services/internal/database/migrations/0001_init.up.sql";
    echo "CREATE TABLE IF NOT EXISTS schema_migrations (";
    echo "    version    integer     PRIMARY KEY,";
    echo "    name       text        NOT NULL,";
    echo "    applied_at timestamptz NOT NULL";
    echo ");";
    echo "INSERT INTO schema_migrations (version, name, applied_at) VALUES (1, 'init', now()) ON CONFLICT (version) DO NOTHING;";
  } | PGPASSWORD=postgres psql -h localhost -p "${PG_PORT}" -U postgres -d civic_commons -v ON_ERROR_STOP=1 -1 >/dev/null
else
  echo "==> Migration 0001 already applied"
fi

# --- Activate the RLS service role (migration 0001 creates it NOLOGIN) -----
echo "==> Activating civic_app role (RLS enforcement, dev password only)"
PGPASSWORD=postgres psql -h localhost -p "${PG_PORT}" -U postgres -d civic_commons -v ON_ERROR_STOP=1 >/dev/null <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = 'civic_app') THEN
    CREATE ROLE civic_app NOLOGIN;
  END IF;
END
\$\$;
ALTER ROLE civic_app LOGIN PASSWORD '${DEV_DB_PASSWORD}';
-- The migration runner (database.Migrate) creates schema_migrations at
-- startup with CREATE TABLE IF NOT EXISTS. PostgreSQL 15+ does NOT grant
-- CREATE on the public schema by default — without it the services crash on
-- first boot with "permission denied for schema public". This grant is
-- required for the service role (dev AND production bootstrap).
GRANT USAGE, CREATE ON SCHEMA public TO civic_app;
-- schema_migrations may already exist owned by the bootstrap role (the
-- migration ran as postgres on first boot); civic_app must be able to read
-- and record applied versions on every startup. Idempotent on fresh DBs.
GRANT SELECT, INSERT, DELETE ON schema_migrations TO civic_app;
SQL
echo "==> civic_app role ready (login, password set, schema usage granted)"

# --- Print the runnable environment ----------------------------------------
if [[ "${1:-}" == "--env" ]]; then
  # PostgreSQL-backed stores (Task 4.5). Uses civic_app so RLS is enforced;
  # never the postgres superuser (it bypasses RLS).
  cat <<EOF
# --- identity service (go run ./cmd/identity) ---
export APP_ENV=development
export SERVICE_NAME=identity
export POSTGRES_DSN='postgres://civic_app:${DEV_DB_PASSWORD}@localhost:${PG_PORT}/civic_commons?sslmode=disable'
export REDIS_ADDR=localhost:${REDIS_PORT}
export PG_ENC_KEY=dev-pgcrypto-key-change-me
export OTP_PROVIDER=noop
# dev secrets (Vault is bypassed in dev; forbidden in production):
export IDENTITY_DEV_SALT_HEX=\$(head -c 32 /dev/urandom | xxd -p -c 64)
export IDENTITY_DEV_JWT_KEY="\$(openssl genrsa 2048 2>/dev/null)"
# HTTP_PORT defaults to 8080 for identity, 8081 for relay — no collision.

# --- relay service (go run ./cmd/relay) ---
export SERVICE_NAME=relay
export REDIS_ADDR=localhost:${REDIS_PORT}
export NATS_URL=nats://localhost:${NATS_PORT}
export IDENTITY_DEV_JWT_PUB_KEY="\$(echo "\$IDENTITY_DEV_JWT_KEY" | openssl rsa -pubout 2>/dev/null)"
# POSTGRES_DSN / PG_ENC_KEY shared with identity above.
EOF
fi

echo
echo "==> Stack ready. Run services from services/:"
echo "    cd services && go run ./cmd/identity   # :8080"
echo "    cd services && go run ./cmd/relay      # :8081"
echo "    Tip: bash scripts/dev_up.sh --env for the full env block"
