# Civic Commons

A privacy-first, local-first civic engagement platform. Civic Commons lets people **Vault** (end-to-end encrypted messaging), read and post to a geo-tagged **Daily Ledger**, contribute to the **War Room** (encrypted civic-issue evidence intake), learn through the **Academy**, and build reputation through a transparent **Karma** system — all designed to work on low-cost Android devices over 2G connections, with **zero plaintext ever stored server-side**.

> **Privacy by architecture, not by policy.** Identity is a blind hash of a phone number (Argon2id), all message content is client-side encrypted (Signal Protocol), and no cloud AI, analytics, or telemetry SDKs are permitted anywhere in the stack.

---

## Project Status

| Phase | Description | Status |
|---|---|---|
| Phase 1 | Environment & CI/CD Setup | ✅ Complete |
| Phase 2 | Local Cryptography & Zero-Knowledge Layer | ✅ Complete |
| Phase 3 | Offline-First SQLite/Queue Repository | ✅ Complete (379 Flutter tests) |
| Phase 4 | API Gateway & Backend Services | ✅ Complete (190 Go tests, all live-verified) |
| Phase 5 | State Management & Sync Engine | ✅ Complete (5.1–5.6, 522 Flutter tests) |
| Phase 6 | Secure Messaging & Device Management | ✅ Complete (6.1–6.6, 824 Flutter tests) |
| **Phase 7** | **The Daily Ledger (Civic Newsroom)** | **✅ Complete (7.1–7.6, 1068 Flutter tests)** |
| **Phase 8** | **War Room** | **⏭ Next — Task 8.1: War Room UI Foundation** |

> **Current:** Phase 7 complete — next: Phase 8, Task 8.1: War Room UI Foundation  
> **Last Updated:** 2026-08-16

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Mobile client** | Flutter 3.x (Dart) · SQLCipher (`vault.db`) · libsignal-protocol-dart · Hive · WorkManager · flutter_secure_storage |
| **Backend services** | Go **1.22** (`services/`) — Identity, Messaging Relay, API Gateway scaffold |
| **API gateway** | Kong OSS 3.x (JWT RS256, rate limiting by blind-hash ID, PII-scrubbed logging) |
| **Relational DB** | PostgreSQL 16 (PostGIS, pgcrypto, row-level security) |
| **Cache & streams** | Redis 7 (Sentinel HA, cache + offline message streams) |
| **Event bus** | NATS JetStream (durable, at-least-once delivery) |
| **Object storage** | MinIO (S3-compatible, SSE-C encrypted) |
| **Search** | Meilisearch (self-hosted) |
| **Secrets** | HashiCorp Vault (KV v2, AppRole auth, Transit engine) |
| **Observability** | Prometheus · Grafana · Loki · Tempo (LGTM stack) |
| **Infrastructure** | Kubernetes 1.29+ · Helm 3 · Terraform · ArgoCD · Hetzner Cloud · Cloudflare |

---

## Repository Layout

```
civic-commons/
├── client/                       # Flutter mobile application (Dart)
│   ├── lib/                      #   Clean-architecture layers
│   │   ├── crypto/               #   Argon2id identity hashing, AES-256-GCM, Ed25519/Curve25519
│   │   ├── signal/               #   X3DH + Double Ratchet (Signal Protocol)
│   │   ├── duress/               #   Duress PIN + decoy-vault selection
│   │   ├── database/             #   SQLCipher schema, migrations, repositories
│   │   ├── identity/             #   Phone hashing, salt management, identity service
│   │   ├── state/                #   BLoC state management (conversation, message, sync, ledger)
│   │   ├── sync/                 #   Background sync worker, reconnection triggers
│   │   ├── repository/           #   Offline-first repos (conversation, message, sync queue)
│   │   ├── relay/                #   WebSocket relay client (protojson wire, first-frame JWT auth)
│   │   ├── pairing/              #   Multi-device pairing (QR key transfer, Ed25519 verification)
│   │   ├── ledger/               #   Daily Ledger (posts, votes, peer review, geo feed)
│   │   ├── geo/                  #   Geographic clustering (coarse pin codes, dynamic radius)
│   │   └── logging/              #   Zero-plaintext redaction logging
│   └── test/                     #   1068 unit + widget tests across all layers
├── services/                     # Go 1.22 backend (standard layout)
│   ├── cmd/
│   │   ├── api/                  #   API gateway entry point
│   │   ├── identity/             #   Identity service (OTP, JWT, blind-hash, devices)
│   │   └── relay/                #   Messaging relay service (WebSocket, offline queue)
│   ├── internal/
│   │   ├── config/               #   Env-based config (secrets never logged)
│   │   ├── database/             #   PostgreSQL migrations + pgcrypto/RLS (+ pgstore impls)
│   │   ├── cache/                #   Redis client factory + Sentinel HA + namespace registry
│   │   ├── events/               #   NATS JetStream client (stream init, durable consumers)
│   │   ├── vault/                #   HashiCorp Vault client (AppRole, KV v2, Transit, cache)
│   │   ├── logging/              #   PII-redacting slog handler (Vault tokens, phones, headers)
│   │   ├── identity/             #   Identity domain (OTP, blind-hash, JWT, refresh tokens)
│   │   ├── relay/                #   Relay domain (WebSocket, Hub, offline queue, conn-req SM)
│   │   ├── idempotency/          #   Server-side idempotency (Redis dedup of sync mutations)
│   │   └── storage/              #   MinIO client factory
│   ├── pkg/version/              #   Build version
│   ├── proto/                    #   Protocol buffer definitions (relay)
│   ├── go.mod                    #   Go 1.22 pinned
│   └── .golangci.yml             #   Strict lint rules (0 violations)
├── infrastructure/
│   ├── helm/
│   │   ├── kong/                 #   Kong OSS 3.x (custom PII-scrub + IP-strip plugins)
│   │   ├── postgresql/           #   PostgreSQL 16
│   │   ├── redis/                #   Redis 7 Sentinel cluster
│   │   ├── nats/                 #   NATS JetStream
│   │   ├── minio/                #   MinIO distributed
│   │   ├── meilisearch/          #   Meilisearch
│   │   ├── observability/        #   Prometheus/Grafana/Loki/Tempo
│   │   └── security/             #   Falco, cert-manager, network policies, PSS
│   ├── argocd/                   #   ArgoCD application manifests
│   ├── database/                 #   PostgreSQL replication + WAL archival configs
│   └── eso/                      #   External Secrets Operator (Vault → K8s)
├── scripts/
│   ├── dev_up.sh                 #   Boot local Postgres/Redis/NATS + RLS role (civic-dedicated ports)
│   ├── verify_kong_gateway.sh    #   Static Kong config verification
│   ├── verify_kong_live.sh       #   Live E2E Kong gateway test
│   ├── verify_redis_live.sh      #   Live Sentinel failover test
│   ├── verify_nats_live.sh       #   Live JetStream durability test
│   ├── verify_vault_live.sh      #   Live Vault AppRole/KV/Transit test
│   ├── verify_go_deps.sh         #   SECURITY CHECKPOINT: blocks cloud AI/telemetry SDKs
│   └── secret-scan.sh            #   Scans for hardcoded secrets
├── documentation/                # PRD, TECHSTACK, DESIGN specs
├── MASTER_PLAN.md                # Phase-by-phase roadmap (source of truth)
├── current_progress.md           # Live progress tracker
└── .github/                      # CI/CD workflows
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| [Go](https://go.dev/dl/) | **1.22** | Backend services (`services/`) — pinned, do not bump |
| [Flutter](https://docs.flutter.dev/get-started/install) | **3.x** | Mobile client (`client/`) |
| [golangci-lint](https://golangci-lint.run/) | v1.64.x | Go static analysis (matches CI) |
| [Docker](https://docs.docker.com/) | — | For live verification scripts (Postgres, Redis, NATS, Vault) |
| PostgreSQL 16 · Redis 7 · NATS · MinIO | — | Local dev or Docker for live verification |

---

## Setup & Run

### Backend (`services/`)

```sh
cd services

# Build & test
go mod tidy              # resolve dependencies (Go 1.22 pinned)
go build ./...           # compile all packages
go test -race ./...      # 190 unit tests with race detector
golangci-lint run        # strict linting (0 violations required)

# Boot the local stack (Postgres :5433, Redis :6381, NATS :4222)
# on civic-dedicated ports + activate the civic_app RLS role
bash scripts/dev_up.sh

# Print the full runnable env block, then run the services:
bash scripts/dev_up.sh --env
cd services
go run ./cmd/identity   # :8080  (OTP, JWT, blind-hash, devices — Postgres + Redis)
go run ./cmd/relay      # :8081  (WebSocket relay — Redis streams, NATS events)
```

### Client (`client/`)

```sh
cd client
flutter pub get
dart analyze              # static analysis (0 errors)
flutter test              # 1068 unit + widget tests
```

### Verification Scripts

All live-verification scripts spin up Docker containers, configure the service, and run end-to-end checks:

```sh
bash scripts/verify_kong_gateway.sh    # Static Kong config check (32 unit tests)
bash scripts/verify_kong_live.sh       # Live E2E: JWT auth, rate limiting, IP stripping
bash scripts/verify_redis_live.sh      # Live: Sentinel failover, namespace TTLs
bash scripts/verify_nats_live.sh       # Live: JetStream durability across broker restart
bash scripts/verify_vault_live.sh      # Live: AppRole auth, KV v2, Transit, token redaction
bash scripts/verify_go_deps.sh         # SECURITY: blocks cloud AI/telemetry SDKs
bash scripts/secret-scan.sh            # SECURITY: scans for hardcoded secrets
```

---

## Architecture Overview

The project follows **Clean Architecture** end to end: domain logic (entities, use cases, abstract ports) is strictly decoupled from data/infrastructure layers (SQLCipher repositories, network, platform APIs). This keeps every layer testable and interchangeable.

**Client (Flutter):** offline-first. All data is read from the local SQLCipher vault and rendered immediately; network operations are queued in a `sync_queue` (encrypted payloads) and retried by WorkManager with exponential backoff (1s → 5m max). A duress-PIN decoy vault (`vault_decoy.db`) is indistinguishable from the real one at rest, and the app never stores which PIN is which.

**Backend (Go services):** each service owns its own tables, communicates via NATS JetStream for events and HTTP/2 internally for gate checks, and never sees plaintext message bodies — the Messaging Relay processes opaque ciphertext envelopes only.

**Security Invariants (enforced in CI):**

| Checkpoint | Enforcement |
|---|---|
| No cloud AI / analytics / telemetry SDKs | `verify_go_deps.sh` — blocks prohibited packages in `go.mod` |
| Raw phone numbers never persisted or logged | Argon2id blind hashing; runtime dump + log scan verified |
| No secrets in application logs | PII-redacting slog handler scrubs phones, Vault tokens, auth headers |
| All sensitive columns encrypted at rest | SQLCipher (client) + pgcrypto (PostgreSQL) — live-verified |
| Secrets in Vault, not env files | `vault.Connect` factory; production refuses to start without Vault auth |
| No decryption server-side | Relay static scan + runtime test prove ciphertext passes through unmodified |
| No plaintext PII in Redis keys | Validated key builders reject non-hex/phone-shaped suffixes |
| No plaintext PII in event payloads | Subject allowlist + `ContainsPII` rejection on subjects and bodies |

---

## Documentation

- [`documentation/Civic_Commons_PRD.md`](documentation/Civic_Commons_PRD.md) — Product Requirements Document
- [`documentation/Civic_Commons_TECHSTACK.md`](documentation/Civic_Commons_TECHSTACK.md) — Implementation-grade technical stack spec
- [`documentation/Civic_Commons_DESIGN.md`](documentation/Civic_Commons_DESIGN.md) — Design system
- [`MASTER_PLAN.md`](MASTER_PLAN.md) — Phase-by-phase implementation roadmap
- [`current_progress.md`](current_progress.md) — Live progress tracker

---

## Changelog

### 2026-08-16 — Phases 5–7 Complete (Sync Engine, Secure Messaging, Daily Ledger)

**Backend (Go) — 190 tests, 0 lint violations, race-clean:**
- **Task 5.3** `internal/idempotency`: server-side Redis dedup of client sync mutations — UUID v4 `Idempotency-Key` header extraction, validated `idempotency:` namespace, in-flight → 409, cached-response replay, 24h TTL
- **Phase 4 services verified end-to-end** against the live local stack: Postgres 16 (4 extensions, RLS-enforced `civic_app` role), Redis 7, NATS JetStream — identity OTP flow returns blind-hash only, relay `/v1/relay/healthz` OK, raw phone numbers absent from all logs

**Client (Flutter) — 1068 tests (379 → 1068), 0 analysis errors:**
- **Phase 5 (State Management & Sync Engine):** debounced network-state detection (online/offline/metered, no IP polling), sync worker + encrypted offline mutation queue (UUID v4 idempotency keys, exponential backoff w/ jitter, crash recovery), sync-status UI (LIVE/CACHED/QUEUED/OFFLINE), deterministic conflict resolution (server-authoritative LWW + blind-hash tie-breaks), durable queue persistence (schema v5, AES-256-GCM sealed payloads)
- **Phase 6 (Secure Messaging & Devices):** Vault UI foundation (FLAG_SECURE), connection-request flow (username search via gateway, BLoC-driven accept/reject), X3DH session establishment + double-ratchet message encrypt/decrypt with explicit `MessageDirection`, WebSocket message relay (`lib/relay/` — protojson wire, first-frame JWT auth, auto-reconnect), multi-device pairing (QR key transfer, real Ed25519 verification, one-time secrets), duress PIN (indistinguishable decoy vault)
- **Phase 7 (The Daily Ledger):** ledger UI foundation, geographic clustering (coarse pin codes, no raw coordinates), dynamic-radius feed, post creation & queuing (sealed envelopes, cold-restart recovery), voting with sub-linear karma weighting (client-side, identity-free by construction), peer-review gate (3/3 consensus, shadow queue, karma fast-track, blinded reviewer handles)

**Security & Compliance (all passed):**
- `secret-scan.sh` passes; `verify_go_deps.sh` passes (no cloud AI/telemetry SDKs, Go 1.22 pinned)
- Zero-PII invariants: raw phones/64-hex hashes/coordinates never in logs, UI, wire frames, or DB rows — verified by security-checkpoint tests in every phase
- All queued mutations sealed with AES-256-GCM before storage; votes/posts/reviews carry zero identity fields by construction

---

### 2026-08-04 — Phase 4 Complete & Workspace Cleanup

**Backend (Go) — 190 tests, 0 lint violations, race-clean:**
- **Identity Service** (`cmd/identity`, `internal/identity`): OTP verification (MSG91), Argon2id phone-to-blind-hash with Vault salt, username claim/release with 30-day cooldown, device public-key registration, stdlib RS256 JWT issuance (15-min access + rotating refresh tokens), PII-redacting logger
- **Messaging Relay** (`cmd/relay`, `internal/relay`): WebSocket connections (coder/websocket, first-frame JWT auth, 25s/10s heartbeat), ciphertext envelope routing with server-verified sender hashes, Redis Streams offline queue (30-day TTL, purge-on-ack), multi-device fan-out, connection-request state machine (pending→accepted/rejected/withdrawn/expired)
- **PostgreSQL** (`internal/database`): Embedded migrations (forward/rollback, advisory-locked), 5 tables (users, usernames, devices, refresh_tokens, connection_requests), RLS with `civic_app`-scoped policies, pgcrypto encryption at rest for device keys
- **Redis** (`internal/cache`): Production client factory with Sentinel HA failover, validated namespace registry with PII-rejecting key builders, AOF+RDB persistence
- **NATS JetStream** (`internal/events`): Stream init, PUBACK publish, durable consumers, auto-reconnect, allowlist topic schema (relay.connection.accepted, identity.user.registered, karma.updated, search.sync.requested)
- **Vault** (`internal/vault`): stdlib net/http client (no SDK) — AppRole login + background token renewal, KV v2 reads + metadata, Transit encrypt/decrypt, TTL-aware SecretCache with rotation detection, WipeBytes zero-memory hygiene, fail-fast `Connect` factory
- **Gateway** (Kong OSS 3.x): JWT RS256 validation, per-blind-hash-id rate limiting, custom PII-scrubbing + IP-stripping plugins, 32 unit tests + live E2E verification

**Client (Flutter) — 379 tests, 0 analysis errors:**
- `dart format` applied across all source and test files (53 files reformatted)
- No `debugPrint()` or `print()` in production code (only in sanctioned `ConsoleLogSink`)
- No TODO/FIXME in production code

**Security & Compliance:**
- `secret-scan.sh` passes (no hardcoded tokens, credentials, or keys)
- `verify_go_deps.sh` passes (no cloud AI/telemetry SDKs in `go.mod`)
- PII-redacting logger verified: scrubs E.164 phones, Vault tokens (`hvs.`/`hvb.`/`hvr.`/`hvc.` + legacy `s.`), `X-Vault-Token` and `Authorization: Bearer` headers
- Production config refuses to start without Vault auth (token or AppRole)
- All Docker test containers cleaned up

---

## License

[MIT](LICENSE) © 2026 Civic Commons Contributors
