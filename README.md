# Civic Commons

A privacy-first, local-first civic engagement platform. Civic Commons lets people **Vault** (end-to-end encrypted messaging), read and post to a geo-tagged **Daily Ledger**, contribute to the **War Room** (encrypted civic-issue evidence intake), learn through the **Academy**, and build reputation through a transparent **Karma** system — all designed to work on low-cost Android devices over 2G connections, with **zero plaintext ever stored server-side**.

> **Privacy by architecture, not by policy.** Identity is a blind hash of a phone number (Argon2id), all message content is client-side encrypted (Signal Protocol), and no cloud AI, analytics, or telemetry SDKs are permitted anywhere in the stack.

---

## Tech Stack

| Layer | Technology |
|---|---|
| **Mobile client** | Flutter 3.x (Dart) · SQLCipher (`vault.db`) · libsignal-protocol-dart · Hive · WorkManager · flutter_secure_storage |
| **Backend services** | Go **1.22+** (`services/`) — Identity, Messaging Relay, Geo-Ledger, War Room, Academy, Karma |
| **API gateway** | Kong OSS 3.x (JWT RS256, rate limiting by blind-hash ID, PII-scrubbed logging) |
| **Relational DB** | PostgreSQL 16 (PostGIS, pgcrypto, row-level security) |
| **Cache & streams** | Redis 7 (cache + offline message streams) |
| **Event bus** | NATS JetStream (durable, at-least-once) |
| **Object storage** | MinIO (S3-compatible, SSE-C encrypted) |
| **Search** | Meilisearch (self-hosted) |
| **Secrets & observability** | HashiCorp Vault · Prometheus/Grafana/Loki/Tempo (LGTM) |
| **Infrastructure** | Kubernetes 1.29+ · Helm 3 · Terraform · ArgoCD · Hetzner Cloud · Cloudflare |

---

## Repository Layout

```
civic-commons/
├── client/                 # Flutter mobile application (Dart)
│   ├── lib/                #   Clean-architecture layers (domain / data / state / crypto / signal)
│   │   ├── crypto/         #   Argon2id identity hashing, salt rotation
│   │   ├── duress/         #   Duress PIN + decoy-vault selection
│   │   ├── database/       #   SQLCipher schema, migrations, repositories
│   │   ├── state/          #   BLoC state management + Hive non-sensitive store
│   │   └── logging/        #   Zero-plaintext redaction logging
│   └── test/               #   Unit + widget tests for every layer
├── services/               # Go 1.22+ backend (standard Go project layout)
│   ├── cmd/                #   Entry points (cmd/api = gateway service binary)
│   ├── internal/           #   Private app/domain code
│   │   ├── config/         #   Env-based config (secrets never logged)
│   │   ├── database/       #   postgres (lib/pq) + sqlcipher drivers
│   │   ├── cache/          #   Redis client factory
│   │   ├── events/         #   NATS connection factory
│   │   └── storage/        #   MinIO client factory
│   ├── pkg/                #   Public shared libraries (pkg/version)
│   ├── proto/              #   Protocol buffer definitions + go:generate
│   ├── go.mod              #   module github.com/kankan223/pari/services (Go 1.22)
│   └── .golangci.yml       #   Strict static-analysis rules
├── infrastructure/         # Terraform / Kubernetes / Helm
├── documentation/          # PRD, TECHSTACK, DESIGN specs
├── scripts/                # Verification & codegen scripts
│   ├── verify_go_deps.sh   #   SECURITY CHECKPOINT: blocks cloud AI/telemetry SDKs
│   ├── generate_proto.sh   #   Protobuf codegen
│   └── verify_flutter_init.sh
└── .github/                # CI/CD workflows
```

---

## Prerequisites

| Tool | Version | Notes |
|---|---|---|
| [Go](https://go.dev/dl/) | **1.22+** | Backend services (`services/`) |
| [Flutter](https://docs.flutter.dev/get-started/install) | **3.x** | Mobile client (`client/`) |
| [golangci-lint](https://golangci-lint.run/) | v1.64.x | Go static analysis (matches CI) |
| PostgreSQL 16 · Redis 7 · NATS · MinIO | — | Local dev dependencies (see TECHSTACK) |

> The Go module is pinned to resolve at `go 1.22.0` (matching the CI toolchain). Do **not** run bare `go get` on pinned dependencies without re-checking the `go` directive — newer `x/*` and `klauspost/compress` releases require Go ≥ 1.23 and will break the Go 1.22 CI pin.

---

## Setup & Run

### Backend (`services/`)

```sh
cd services
go mod tidy          # resolve dependencies (no conflicts)
go build ./...       # compile all packages
go test -race ./...  # unit tests
golangci-lint run    # strict linting (0 violations required)

# Run the (minimal, scaffolded) API entry point:
# Configuration comes from environment variables; POSTGRES_DSN is required.
POSTGRES_DSN="postgres://user:pass@localhost:5432/civic?sslmode=disable" \
  go run ./cmd/api
```

The entry point currently prints only non-secret metadata (build version + environment). The actual gateway (HTTP server, JWT auth, routing) lands in later Phase 4 tasks.

### Client (`client/`)

```sh
cd client
flutter pub get
dart analyze        # static analysis (0 errors; a few pre-existing info-level style nits in tests remain)
flutter test        # full unit test suite (crypto, duress, database, state, sync, ...)
```

### Scripts

```sh
./scripts/verify_go_deps.sh   # SECURITY CHECKPOINT: deny-list scan of go.mod + go.sum
./scripts/generate_proto.sh   # regenerate protobuf Go code (requires protoc + protoc-gen-go)
```

---

## Architecture Overview

The project follows **Clean Architecture** end to end: domain logic (entities, use cases, abstract ports) is strictly decoupled from data/infrastructure layers (SQLCipher repositories, network, platform APIs). This keeps every layer testable and interchangeable.

**Client (Flutter):** offline-first. All data is read from the local SQLCipher vault and rendered immediately; network operations are queued in a `sync_queue` (encrypted payloads) and retried by WorkManager with exponential backoff (1s → 5m max). A duress-PIN decoy vault (`vault_decoy.db`) is indistinguishable from the real one at rest, and the app never stores which PIN is which.

**Backend (Go services):** each service owns its own tables, communicates via NATS JetStream for events and HTTP/2 internally for gate checks, and never sees plaintext message bodies — the Messaging Relay processes opaque ciphertext envelopes only.

**Security invariants (enforced in CI):**
- No cloud AI / analytics / telemetry SDKs in Go dependencies (`verify_go_deps.sh`)
- Raw phone numbers are never persisted, stored, or logged (Argon2id blind hashing)
- All sensitive columns encrypted at rest (SQLCipher / pgcrypto); secrets live in HashiCorp Vault, never in env-based config files or logs

---

## Documentation

- [`documentation/Civic_Commons_PRD.md`](documentation/Civic_Commons_PRD.md) — Product Requirements Document
- [`documentation/Civic_Commons_TECHSTACK.md`](documentation/Civic_Commons_TECHSTACK.md) — Implementation-grade technical stack spec
- [`documentation/Civic_Commons_DESIGN.md`](documentation/Civic_Commons_DESIGN.md) — Design system
- [`MASTER_PLAN.md`](MASTER_PLAN.md) — Phase-by-phase implementation roadmap
- [`current_progress.md`](current_progress.md) — Live progress tracker

---

## License

[MIT](LICENSE) © 2026 Civic Commons Contributors
