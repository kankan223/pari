# Civic Commons — Go Services

Phase 4 backend foundation (API Gateway & backend services), Go 1.22+.

## Layout (standard Go project layout)

```
services/
├── cmd/                    # entry points
│   ├── api/                #   API gateway service binary (scaffold)
│   ├── identity/           #   Identity Service binary (Task 4.3)
│   └── relay/              #   Messaging Relay Service binary (Task 4.4)
├── internal/               # private application/domain logic
│   ├── config/             #   env-based configuration (never logs secrets)
│   ├── database/           #   DB open helpers (postgres + sqlcipher drivers)
│   ├── cache/              #   Redis client factory
│   ├── events/             #   NATS JetStream event bus (streams, durable consumers, topic schema)
│   ├── storage/            #   MinIO client factory
│   ├── vault/              #   HashiCorp Vault client (KV v2, AppRole, transit, renewal — stdlib net/http)
│   ├── logging/            #   shared PII-redacting slog handler
│   ├── identity/           #   Identity Service: OTP, Argon2id blind-hash,
│   │                       #   username cooldown, devices, JWT + refresh
│   └── relay/              #   Messaging Relay: WS pump + hub (fan-out),
│                           #   Redis Streams offline queue, connection
│                           #   requests (protojson framing)
├── pkg/                    # public/shared library code
│   └── version/
├── proto/                  # protocol buffer definitions + go:generate
│   └── relay.proto         #   relay wire protocol (envelope/auth/ack/error)
├── go.mod                  # module github.com/kankan223/pari/services (Go 1.22)
├── go.sum
├── .golangci.yml           # strict static-analysis rules
└── tools.go                # pinned codegen tool versions (build-tagged)
```

## Module & dependencies

Pinned direct dependencies (see `go.mod`; also maintained by `go mod tidy`):

- `github.com/mutecomm/go-sqlcipher` — SQLCipher driver (blank import, driver name `sqlite3`)
- `github.com/lib/pq` — PostgreSQL driver (blank import, driver name `postgres`)
- `github.com/redis/go-redis/v9` — Redis client
- `github.com/nats-io/nats.go` — NATS client (JetStream event bus)
- `github.com/nats-io/nats-server/v2` — embedded JetStream server (test-only)
- `github.com/coder/websocket` — WebSocket library (relay; no stdlib WS in Go)
- `github.com/minio/minio-go/v7` — MinIO S3 client
- `golang.org/x/crypto` — `argon2` (blind-hash) + `bcrypt` (OTP codes)
- `google.golang.org/protobuf` — protobuf runtime + `protoc-gen-go` (tool pin)
- `github.com/alicebob/miniredis/v2` — **test-only** in-process Redis for unit tests

No JWT, Vault, or SMS SDKs are imported: RS256 JWT is implemented on
`crypto/rsa` (stdlib), Vault is accessed via a ~600-line `net/http` client
(`internal/vault` — KV v2 reads + metadata, AppRole login, token
lookup/renew with a background renewal loop, transit encrypt/decrypt,
TTL-aware `SecretCache` with rotation detection, `WipeBytes`), and the MSG91
provider is a `net/http` REST call — per the project's minimal-dependency
directive.

## Tooling

```sh
go mod tidy          # resolve deps (no conflicts)
go vet ./...         # static analysis
go test -race ./...  # unit tests
golangci-lint run    # strict linters (see .golangci.yml)
./scripts/generate_proto.sh   # regenerate protobuf Go code (go generate)
./scripts/verify_go_deps.sh   # SECURITY CHECKPOINT: no cloud AI/telemetry SDKs
```

## Identity Service (Task 4.3)

```sh
# Dev run (no Vault): IDENTITY_DEV_* fallbacks are forbidden in production.
#
# The services need PostgreSQL (Task 4.5), Redis (Task 4.6) and optionally
# NATS (Task 4.7) running. The fastest path is the dev stack bootstrap:
#
#   bash scripts/dev_up.sh --env   # starts civic-postgres:5433, civic-redis:6381,
#                                  # civic-nats:4222, activates the civic_app role,
#                                  # and prints the full env block (eval-able)
#
# NOTES (all three matter — each has broken naive dev runs before):
#  1. The civic PostgreSQL container publishes on 5433, NOT 5432. Port 5432 is
#     an unrelated project's database on this machine; pointing POSTGRES_DSN at
#     it yields "password authentication failed" (or worse, writes into the
#     wrong database).
#  2. Use the civic_app role (activated with a dev password by dev_up.sh), NOT
#     the postgres superuser — a superuser BYPASSES row-level security, silently
#     defeating the Task 4.5 RLS checkpoint.
#  3. Point REDIS_ADDR at the civic Redis (6381). Port 6379 is another
#     project's instance; reusing it risks key collisions.
#
# Manual equivalent:
openssl genrsa -out /tmp/dev_rsa.pem 2048
export APP_ENV=development
export POSTGRES_DSN='postgres://civic_app:civic_app_dev@localhost:5433/civic_commons?sslmode=disable'
export REDIS_ADDR=localhost:6381
export PG_ENC_KEY=dev-pgcrypto-key-change-me
export IDENTITY_DEV_SALT_HEX=$(head -c 32 /dev/urandom | xxd -p -c 64)
export IDENTITY_DEV_JWT_KEY="$(cat /tmp/dev_rsa.pem)"
go run ./cmd/identity   # HTTP_PORT defaults to 8080
```

Production requires `VAULT_ADDR` + `VAULT_TOKEN` (or `VAULT_ROLE_ID` +
`VAULT_SECRET_ID` for AppRole auth — config refuses to run without one in
non-dev; `VAULT_RENEW_INTERVAL` defaults to 5m and drives the background
token-renewal loop). Salt + RS256 key are fetched from KV v2 at startup and
sealed in `sync.Once`; `SecretCache` re-reads them on rotation. `MSG91_API_KEY`
(or `OTP_PROVIDER=noop`) and `REDIS_ADDR` are also required.

Endpoints (`/v1/identity`): `otp/request`, `otp/verify`, `username/claim`,
`username/release`, `devices` (POST/GET/DELETE), `token/refresh`,
`token/revoke`, `me`. Access tokens are RS256 JWTs (15 min, `kid` header for
Kong); refresh tokens are opaque 256-bit values stored hashed in Redis
(`refresh:`/`revoked:`/`revoked_family:` namespaces, 30-day TTL) with
rotation + reuse detection. OTP codes live in Redis (`otp:` namespace,
10-min TTL, bcrypt-hashed values, 5-attempt cap).

## Messaging Relay Service (Task 4.4)

```sh
# Dev run: same JWT keypair the identity service signs with. Reuse the
# POSTGRES_DSN / REDIS_ADDR / PG_ENC_KEY from the identity block above, or
# just run `bash scripts/dev_up.sh --env` once and source the output.
openssl genrsa -out /tmp/dev_rsa.pem 2048
export APP_ENV=development
export POSTGRES_DSN='postgres://civic_app:civic_app_dev@localhost:5433/civic_commons?sslmode=disable'
export REDIS_ADDR=localhost:6381
export PG_ENC_KEY=dev-pgcrypto-key-change-me
export IDENTITY_DEV_JWT_KEY="$(cat /tmp/dev_rsa.pem)"  # derives the public key in dev
go run ./cmd/relay   # HTTP_PORT defaults to 8081, WS at /v1/relay/ws
```

The relay's default HTTP port is 8081 (it sets it itself when HTTP_PORT is
unset), so identity (:8080) and relay can run side by side.

Production requires `VAULT_ADDR` + `VAULT_TOKEN` (or AppRole creds — RS256
public key fetched from KV v2 `identity/jwt_rs256_public_key`),
`REDIS_ADDR`, and optionally `NATS_URL` (noop event publisher fallback in dev).

## NATS JetStream event bus (Task 4.7)

The relay publishes domain events (e.g. `relay.connection.accepted`) to the
`CIVIC_EVENTS` JetStream stream with **at-least-once** delivery: publishers
wait for a PUBACK, and durable consumers ack explicitly (a handler error NAKs
for redelivery; ack progress survives broker restarts). Subjects are an
**allowlist** (`relay.connection.accepted`, `identity.user.registered`,
`karma.updated`, `search.sync.requested`) — subjects and payloads carrying
E.164 phones / e-mails are rejected (zero plaintext PII).

Config: `NATS_URL`, `NATS_STREAM_NAME` (default `CIVIC_EVENTS`),
`NATS_STORAGE` (`file`|`memory`), `NATS_MAX_AGE` (30d),
`NATS_MAX_RECONNECTS` (default -1/infinite), `NATS_RECONNECT_WAIT`,
`NATS_CONNECT_TIMEOUT`. Run the live verification with
`bash scripts/verify_nats_live.sh` (docker nats container, pub/sub +
broker-restart durability + PII checks).

Endpoints: `GET /v1/relay/ws` (WebSocket — first frame must be a protojson
`AuthRequest{access_token, device_id}`; 25s ping / 10s pong heartbeat),
`POST|GET /v1/relay/requests` and `POST /v1/relay/requests/{id}/accept|reject|withdraw`
(Bearer auth). Wire protocol in `proto/relay.proto`.

### Idempotency (Task 5.3)

Every **mutation** endpoint (`POST /v1/relay/requests` and the accept/reject/
withdraw actions) runs inside the idempotency middleware: the client's
`Idempotency-Key` header (UUID v4, generated per mutation — Task 5.2) is
deduped in Redis for 24h (`IDEMPOTENCY_TTL`), so a retried mutation is never
applied twice. Semantics: missing header → non-idempotent passthrough;
malformed key (not a UUID v4) → 400; key in-progress → **409 Conflict**;
key completed → the cached response is replayed (with `Idempotent-Replayed:
true`) without re-running the handler; a failed handler clears the key so the
next retry reprocesses. Keys live under the validated `idempotency:`
namespace (`idempotency:{blind_hash_id}:{uuid}` — actor-scoped so one user
can never read another user's cached response; the builder rejects any
non-UUID/PII shape before it can reach Redis). Implemented in
`internal/idempotency` (Redis SETNX claim / GET / SET / DEL against the same
Sentinel-HA client).

**Zero-knowledge:** the relay is a ciphertext router. It never decrypts or
inspects message bodies — `Envelope.ciphertext` is opaque bytes routed
unmodified (enforced by a static decryption-primitive scan + runtime
pass-through tests). Sender identities are always server-derived from the
access token; client-supplied `sender_hash`/`sender_device_id` are ignored.

## Redis configuration (Task 4.6)

Both services build their Redis client via `cache.NewClient(cache.Options{...})`
(`internal/cache/redis.go`). Set `REDIS_SENTINEL_ADDRS` (comma-separated) to
enable **Sentinel HA failover**; the go-redis failover client follows the
elected master transparently (live-verified: killing the primary promotes a
replica and the client keeps working). Tuning env vars (with defaults):
`REDIS_POOL_SIZE` (20), `REDIS_MIN_IDLE_CONNS` (5), `REDIS_MAX_RETRIES` (3,
8ms→512ms backoff), `REDIS_DIAL/READ/WRITE/POOL_TIMEOUT` (5s/3s/3s/4s),
`REDIS_SENTINEL_MASTER` (civic-master), `REDIS_SENTINEL_PASSWORD`. A startup
`Ping` health probe is logged (non-fatal).

### Key namespaces (strict, validated)

Every Redis key is built through `internal/cache/namespaces.go` builders that
**reject any PII-shaped suffix** (raw phones, OTPs, emails, non-hex strings):

| Namespace | Suffix | TTL | Used by |
|---|---|---|---|
| `otp:` | 64-hex blind_hash_id | 10m | identity OTP codes (bcrypt value) |
| `otp_attempts:` | 64-hex blind_hash_id | 10m | identity OTP brute-force cap |
| `refresh:` | SHA-256 digest | 30d | identity refresh tokens |
| `revoked:` | SHA-256 digest | 30d | rotated/revoked tokens |
| `revoked_family:` | 32-hex family id | 30d | family-wide reuse detection |
| `msg_queue:` | 64-hex blind_hash_id | 30d/msg | relay offline queue (Streams) |
| `karma:` / `vote_buffer:` / `analyst_load:` / `rate:` | (reserved) | spec | future services |

Run the live verification (docker Sentinel cluster + failover demo):
`bash scripts/verify_redis_live.sh`.

## Vault integration (Task 4.8)

Services authenticate with Vault via a static token or **AppRole**
(`VAULT_ROLE_ID`/`VAULT_SECRET_ID`) and the client renews its token in the
background (`VAULT_RENEW_INTERVAL`, re-login on failure). Secrets are cached
through a TTL-aware `SecretCache` whose `Refresh` detects rotation, and
memory hygiene is enforced with `WipeBytes`. Transit encrypt/decrypt helpers
are available for key-wrapping needs.

**Secrets are never logged:** the shared redacting logger scrubs Vault token
shapes (`hvs.`/`s.`), `X-Vault-Token:` and `Authorization: Bearer` headers,
and `X-Vault-*` request headers. Production config refuses to start without
Vault auth (no silent unauthenticated fallback).

Run the live verification with `bash scripts/verify_vault_live.sh` (docker
Vault dev server: KV v2 + transit + AppRole login + wrong-token rejection +
redaction checks).

## Idempotency (Task 5.3)

The relay dedupes retried client mutations by their `Idempotency-Key` header:

| Header state | Behaviour |
|---|---|
| missing | non-idempotent passthrough (legacy/internal callers) |
| malformed (not UUID v4) | 400 — rejected before any Redis/handler work |
| key in-progress | 409 Conflict (concurrent duplicate) |
| key completed | replay cached response + `Idempotent-Replayed: true` |
| key absent | process, cache the 2xx response (TTL 24h, `IDEMPOTENCY_TTL`) |
| handler failed | key cleared — next retry reprocesses |

Security: dedup keys are **actor-scoped** (`idempotency:{blind_hash_id}:{uuid}`
via `cache.IdempotencyKeyScoped`) and the cache builder strictly validates the
UUID v4 shape — a phone/e-mail/free-form string can never become a Redis key
(Task 4.6 checkpoint maintained). The cached body is the JSON the handler
already returned (blind hashes, never PII). `internal/idempotency` contains
the Redis store (atomic SETNX claim) + the middleware; relay wiring in
`cmd/relay/main.go` + `internal/relay/server.go` (inside the auth chain).

## Security posture

- No cloud-based AI, analytics, or telemetry SDKs are permitted in Go
  dependencies — enforced by `scripts/verify_go_deps.sh` (deny-list scan of
  `go.mod` + `go.sum`).
- Configuration is read from environment variables; secrets are never logged
  (incl. Vault tokens/auth headers — redacted by `internal/logging`).
- All data-layer work is SQLCipher-encrypted at rest / TLS-in-transit by design.
- The relay service never attempts to decrypt message bodies (see above).
- The Identity Service never persists or logs raw phone numbers: E.164
  numbers are Argon2id-hashed immediately (buffer zeroed afterwards), OTP
  codes are stored bcrypt-hashed, and every log line passes a PII redactor
  (E.164 + e-mail patterns → `[REDACTED]`). Enforced by dedicated
  security-checkpoint tests.
