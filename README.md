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
| **Phase 5** | **State Management & Sync Engine** | **▶ In Progress — Task 5.1** |

> **Current:** Phase 5 — Task 5.1: Network State Detection  
> **Last Updated:** 2026-08-04

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
│   │   ├── state/                #   BLoC state management (conversation, message, sync)
│   │   ├── sync/                 #   Background sync worker, reconnection triggers
│   │   ├── repository/           #   Offline-first repos (conversation, message, sync queue)
│   │   └── logging/              #   Zero-plaintext redaction logging
│   └── test/                     #   379 unit + widget tests across all layers
├── services/                     # Go 1.22 backend (standard layout)
│   ├── cmd/
│   │   ├── api/                  #   API gateway entry point
│   │   ├── identity/             #   Identity service (OTP, JWT, blind-hash, devices)
│   │   └── relay/                #   Messaging relay service (WebSocket, offline queue)
│   ├── internal/
│   │   ├── config/               #   Env-based config (secrets never logged)
│   │   ├── database/             #   PostgreSQL migrations + pgcrypto/RLS
│   │   ├── cache/                #   Redis client factory + Sentinel HA + namespace registry
│   │   ├── events/               #   NATS JetStream client (stream init, durable consumers)
│   │   ├── vault/                #   HashiCorp Vault client (AppRole, KV v2, Transit, cache)
│   │   ├── logging/              #   PII-redacting slog handler (Vault tokens, phones, headers)
│   │   ├── identity/             #   Identity domain (OTP, blind-hash, JWT, refresh tokens)
│   │   ├── relay/                #   Relay domain (WebSocket, Hub, offline queue, conn-req SM)
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

# Run Identity Service
IDENTITY_DEV_SALT_HEX="64-hex-chars" \
  go run ./cmd/identity

# Run Messaging Relay
IDENTITY_DEV_JWT_PUB_KEY="your-rs256-public-key" \
  go run ./cmd/relay
```

### Client (`client/`)

```sh
cd client
flutter pub get
dart analyze              # static analysis (0 errors)
flutter test              # 379 unit + widget tests
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
