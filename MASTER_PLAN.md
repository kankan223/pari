# Civic Commons — Master Implementation Plan

**Version:** 1.0  
**Status:** Active  
**Last Updated:** 2026-08-05  
**Role:** Single Source of Truth for All Development Work

---

## Overview

This document is the authoritative implementation roadmap for building The Civic Commons platform from scratch. All development work must follow this plan sequentially. No task may be skipped, and no phase may be bypassed.

**Critical Directive:** Before writing any code, consult this plan. Execute tasks in order. Check off completed items immediately. Do not proceed to UI development until the local data, queuing, and cryptographic layers are fully tested and verified.

---

## Phase 1: Environment & CI/CD Setup

### Objective
Establish the foundational development environment, infrastructure-as-code, and continuous integration pipeline to support secure, compliant development across all phases.

### 1.1 Repository & Development Environment Setup
- [x] Initialize Git repository with main branch protection rules
- [x] Create `.gitignore` with exclusions for: `.env`, `*.key`, `*.pem`, `build/`, `.dart_tool/`, `node_modules/`, secrets
- [x] Set up pre-commit hooks: `husky` for linting, format checking, and secret scanning (using custom script)
- [x] Configure `commitlint` with conventional commit format enforcement
- [x] Create directory structure following the technical stack specification:
  ```
  /client (Flutter)
  /services (Go microservices)
  /infrastructure (Terraform, Helm)
  /docs (API specs, architecture diagrams)
  /scripts (deployment, utilities)
  ```
- [x] VERIFY: Run secret scanning script to confirm secret scanning is operational
- [x] VERIFY: Test pre-commit hook with a dummy commit containing a fake API key to confirm rejection

### 1.2 Infrastructure as Code (Terraform)
- [x] Set up Terraform workspace for Hetzner Cloud (eu-central region)
- [x] Define VPC networking with private subnet for database cluster
- [x] Create Kubernetes cluster (1.29+) with node pool configuration
- [x] Define Cloudflare CDN and DDoS protection resources
- [x] Create MinIO distributed mode storage resources (4 nodes, 2 drives each)
- [x] Set up HashiCorp Vault instance for secrets management
- [x] VERIFY: Run `terraform plan` and confirm no destructive changes to existing infrastructure
- [x] VERIFY: Validate Terraform configuration with `tflint` and `checkov` for security compliance

### 1.3 Kubernetes Infrastructure (Helm & ArgoCD)
- [x] Install Helm 3 and configure Helm repositories
- [x] Create Helm charts for: PostgreSQL, Redis, MinIO, NATS, Meilisearch
- [x] Set up ArgoCD for GitOps deployment
- [x] Configure ArgoCD application manifests for all infrastructure components
- [x] Define secrets management strategy: External Secrets Operator syncing from HashiCorp Vault
- [x] VERIFY: Deploy test namespace and confirm ArgoCD syncs successfully
- [x] VERIFY: Test secret injection by creating a test secret in Vault and confirming it appears in Kubernetes

### 1.4 CI/CD Pipeline (GitHub Actions / GitLab CI)
- [x] Create CI pipeline for Flutter client: lint, analyze, unit tests, build APK/IPA
- [x] Create CI pipeline for Go services: gofmt, go vet, unit tests, race detector, security scan (`gosec`)
- [x] Create infrastructure validation pipeline: Terraform plan, `tflint`, `checkov`
- [x] Set up automated dependency scanning: `dependabot` or Renovate
- [x] Configure artifact signing for production builds
- [x] VERIFY: Trigger CI pipeline on a test commit and confirm all jobs pass
- [x] VERIFY: Test security scanner by intentionally adding a vulnerable dependency and confirm pipeline failure

### 1.5 Observability Stack (LGTM)
- [x] Deploy Prometheus with service discovery for Kubernetes
- [x] Deploy Grafana with pre-configured dashboards for: system health, API latency, error rates
- [x] Deploy Loki for log aggregation with PII-scrubbing configuration
- [x] Deploy Tempo for distributed tracing
- [x] Configure log scrubbing rules: redact phone numbers, emails, blind_hash_id patterns
- [x] VERIFY: Ingest test logs containing fake PII and confirm Loki stores only scrubbed versions
- [x] VERIFY: Generate test trace data and confirm it appears in Tempo with proper span correlation

### 1.6 Security Baseline
- [x] Configure Falco for runtime security monitoring
- [x] Set up network policies in Kubernetes (deny-all, allow-specific)
- [x] Configure pod security standards (restricted) for all workloads
- [x] Set up automated backup for PostgreSQL WAL to MinIO
- [x] Configure SSL/TLS certificates with cert-manager for all ingress
- [x] VERIFY: Run a pod with privileged container and confirm Falco detects and alerts
- [x] VERIFY: Test network policy by attempting unauthorized inter-pod communication and confirm denial

---

## Phase 2: Local Cryptography & Zero-Knowledge Layer

### Objective
Implement the client-side cryptographic foundation that ensures zero-knowledge architecture: all encryption happens on-device, keys never leave the secure enclave, and servers only ever handle ciphertext.

### 2.1 Flutter Project Initialization
- [x] Create Flutter 3.x project with minimum SDK constraint matching tech stack
- [x] Configure `pubspec.yaml` with pre-approved dependencies only (libsignal, sqflite_sqlcipher, etc.)
- [x] Set up Flutter linter rules in `analysis_options.yaml`
- [x] Configure code coverage for unit tests
- [x] VERIFY: Run `flutter pub get` and confirm no dependency conflicts
- [x] SECURITY CHECKPOINT: Confirm no cloud-based AI or analytics SDKs are in dependencies

### 2.2 Cryptography Service Foundation
- [x] Create `lib/crypto/crypto_service.dart` with abstract interface for encryption/decryption
- [x] Implement Argon2id key derivation for PIN-to-database-key (memory=64MB, iterations=3, parallelism=4)
- [x] Implement Ed25519 key pair generation for identity keys
- [x] Implement Curve25519 key pair generation for Signal Protocol prekeys
- [x] Create key storage wrapper using `flutter_secure_storage` with hardware-backed keystore
- [x] VERIFY: Write unit tests for Argon2id derivation with known test vectors
- [x] VERIFY: Write unit tests for key generation and confirm keys are not exportable from secure storage
- [x] SECURITY CHECKPOINT: Confirm no private keys are ever written to SQLite or logged

### 2.3 Signal Protocol Implementation
- [x] Implement X3DH key agreement protocol using `libsignal_protocol_dart`
- [x] Implement Double Ratchet session encryption
- [x] Create prekey management system: signed prekey rotation (7 days), one-time prekey batch (100 keys)
- [x] Implement session state storage in SQLCipher database
- [x] Create public key bundle API structure for sharing with other users
- [x] VERIFY: Write unit tests for X3DH handshake with known test vectors
- [x] VERIFY: Write unit tests for Double Ratchet forward secrecy (confirm message keys are discarded)
- [x] SECURITY CHECKPOINT: Confirm message content is never decrypted server-side in tests

### 2.4 Identity Hashing (Phone Number to Blind Hash)
- [x] Implement Argon2id hashing for phone numbers with salt fetched from secure backend
- [x] Create phone number validation (E164 format)
- [x] Implement salt rotation logic (quarterly) with fallback support
- [x] Create blind hash ID generation and storage
- [x] VERIFY: Write unit tests for phone hashing with known salt and confirm output matches expected hash
- [x] VERIFY: Write unit tests for salt rotation and confirm old hashes can still be validated
- [x] SECURITY CHECKPOINT: Confirm raw phone numbers are never persisted to disk or logged

### 2.5 Duress PIN Implementation
- [x] Implement dual PIN registration flow (real PIN + duress PIN)
- [x] Create separate database key derivation paths for each PIN
- [x] Implement decoy database (`vault_decoy.db`) initialization
- [x] Create database selection logic based on which PIN successfully decrypts
- [x] VERIFY: Write unit tests for duress PIN unlocking decoy database
- [x] VERIFY: Write unit tests for real PIN unlocking real database
- [x] SECURITY CHECKPOINT: Confirm app never stores which PIN is real vs duress

### 2.6 Hardware Security Integration
- [x] Implement `FLAG_SECURE` wrapper for Android using platform channel
- [x] Create secure screen wrapper widget for Vault and War Room screens
- [x] Implement root/jailbreak detection (local only, no telemetry)
- [x] Create graceful degradation flow for rooted devices (warning, not block)
- [x] VERIFY: Test on Android device and confirm screenshot is blocked when FLAG_SECURE is active
- [x] VERIFY: Test on rooted device and confirm warning appears without sending telemetry
- [x] SECURITY CHECKPOINT: Confirm no device fingerprinting data is sent to server

### 2.7 Zero-Plaintext Logging System
- [x] Create custom logging wrapper that redacts PII patterns
- [x] Implement hash-only logging for sensitive operations (log hash IDs, not raw data)
- [x] Add boolean success/fail logging for cryptographic operations
- [x] Configure logging levels for development vs production
- [x] VERIFY: Write unit tests that attempt to log PII and confirm redaction occurs
- [x] VERIFY: Write unit tests for hash-only logging and confirm reversibility is impossible
- [x] SECURITY CHECKPOINT: Confirm no `print()` or `debugPrint()` outputs raw payload data

---

## Phase 3: Offline-First SQLite/Queue Repository

### Objective
Build the local data layer with SQLCipher encryption and a queue-based sync system that ensures the app works offline and syncs resiliently when connectivity returns.

### 3.1 SQLCipher Database Schema Design
- [x] Define Drift/SQLCipher schema for core entities:
  - `users` (blind_hash_id, username, device_pubkey)
  - `conversations` (id, participant_hash, encrypted_session_state)
  - `messages` (id, conversation_id, ciphertext, delivered, expires_at)
  - `connection_requests` (id, requester_hash, recipient_hash, status)
  - `sync_queue` (id, operation_type, payload, status, retry_count)
- [x] Create database migration system
- [x] Implement database key derivation from user PIN (Argon2id)
- [x] VERIFY: Write unit tests for schema creation and migration
- [x] VERIFY: Write unit tests for database encryption/decryption with wrong key failure
- [x] SECURITY CHECKPOINT: Confirm all sensitive columns are encrypted at rest

### 3.2 Repository Pattern Implementation
- [x] Create abstract `BaseRepository` class with standard CRUD operations
- [x] Implement `ConversationRepository` for Vault data
- [x] Implement `MessageRepository` with local-first read/write
- [x] Implement `SyncQueueRepository` for pending operations
- [x] Create repository interface that returns local data immediately, then syncs
- [x] VERIFY: Write unit tests for repository CRUD operations
- [x] VERIFY: Write unit tests for repository returning cached data before sync
- [x] SECURITY CHECKPOINT: Confirm repositories never make direct HTTP calls

### 3.3 Sync Queue Implementation
- [x] Create `SyncQueueItem` model with fields: operation_type, payload, status, retry_count, created_at
- [x] Implement queue status enum: `pending`, `in_progress`, `success`, `failed`
- [x] Create queue insertion logic for all mutation operations (POST, PUT, DELETE)
- [x] Implement retry logic with exponential backoff (1s, 2s, 4s ... 5 min max)
- [x] VERIFY: Write unit tests for queue insertion and status transitions
- [x] VERIFY: Write unit tests for exponential backoff calculation
- [x] SECURITY CHECKPOINT: Confirm queued payloads are encrypted before storage

### 3.4 WorkManager Background Sync
- [x] Configure `workmanager` plugin for background task execution
- [x] Create background sync worker that processes pending queue items
- [x] Implement network state detection using `connectivity_plus`
- [x] Create sync trigger on network reconnection
- [x] Implement chunking logic for batch operations (max 10 items per batch)
- [x] VERIFY: Write integration tests for background sync execution
- [x] VERIFY: Write unit tests for network state detection
- [x] SECURITY CHECKPOINT: Confirm background sync respects offline-first architecture

### 3.5 Local State Management (BLoC/Cubit)
- [x] Create BLoC for conversation state (streams from local database)
- [x] Create BLoC for message state (streams from local database)
- [x] Create BLoC for sync status (LIVE, CACHED, QUEUED, OFFLINE)
- [x] Implement state persistence using Hive for non-sensitive data
- [x] VERIFY: Write unit tests for BLoC state transitions
- [x] VERIFY: Write unit tests for database stream emissions to BLoC
- [x] SECURITY CHECKPOINT: Confirm BLoC never exposes raw decrypted data in logs

### 3.6 Hive Local Storage for Non-Sensitive Data
- [x] Create Hive boxes for: ledger_drafts, academy_progress, karma_cache
- [x] Implement Hive initialization with encryption for sensitive boxes
- [x] Create cache invalidation logic for karma scores (5 min TTL)
- [x] VERIFY: Write unit tests for Hive CRUD operations
- [x] VERIFY: Write unit tests for cache invalidation TTL logic
- [x] SECURITY CHECKPOINT: Confirm no PII or sensitive data in unencrypted Hive boxes

---

## Phase 4: API Gateway & Backend Services Foundation

### Objective
Build the API Gateway layer and core backend services in Go, implementing the service boundary architecture defined in the technical stack.

### 4.1 Go Project Structure & Dependencies
- [x] Create Go 1.22+ project with standard layout: `/cmd`, `/internal`, `/pkg`
- [x] Initialize Go modules with pinned versions from TECHSTACK.md
- [x] Add dependencies: `go-sqlcipher`, `lib/pq`, `go-redis`, `nats.go`, `minio-go`
- [x] Configure `golangci-lint` with custom rules
- [x] Set up `go generate` for protocol buffer compilation
- [x] VERIFY: Run `go mod tidy` and confirm no dependency conflicts
- [x] VERIFY: Run `golangci-lint run` and confirm no violations
- [x] SECURITY CHECKPOINT: Confirm no cloud-based AI or telemetry SDKs in Go dependencies

### 4.2 API Gateway (Kong OSS)
- [x] Deploy Kong OSS 3.x via Helm chart
- [x] Configure JWT plugin with RS256 validation
- [x] Configure rate-limiting-advanced plugin per blind_hash_id *(implemented as OSS `rate-limiting`, `limit_by: consumer` — `rate-limiting-advanced` is Kong Enterprise-only; drop-in upgrade path documented in-file)*
- [x] Configure request-transformer to strip X-Forwarded-For
- [x] Configure response-transformer to remove server headers
- [x] Configure bot-detection plugin
- [x] Configure correlation-id injection
- [x] Configure PII scrubbing for access logs
- [x] VERIFY: Test JWT validation with invalid token and confirm 401 response
- [x] VERIFY: Test rate limiting with rapid requests and confirm throttling
- [x] SECURITY CHECKPOINT: Confirm IP addresses are stripped before upstream requests

### 4.3 Identity Service (Go)
- [x] Implement OTP verification endpoint (Twilio Verify or MSG91 integration) *(MSG91 chosen — India/DPDP fit; net/http v5 OTP REST client, no SDK; noop provider for dev)*
- [x] Implement Argon2id phone-to-blind-hash with salt from HashiCorp Vault *(params byte-identical to client PhoneHasher; salt fetched once at startup into a sealed sync.Once; minimal KV v2 HTTP client, no SDK)*
- [x] Implement username claim/release with cooldown (30 days)
- [x] Implement device public-key registration
- [x] Implement JWT issuance (RS256, 15-minute access tokens) *(stdlib crypto/rsa RFC 7519 implementation; kid header for Kong)*
- [x] Implement refresh token management with rotation *(256-bit opaque tokens, SHA-256 hashes in Redis, family-based reuse detection)*
- [x] Configure Redis for OTP codes (TTL 10 min) and refresh token revocation *(otp: 10-min bcrypt-hashed; refresh:/revoked:/revoked_family: 30-day)*
- [x] VERIFY: Write unit tests for OTP verification flow
- [x] VERIFY: Write unit tests for JWT issuance and validation
- [x] SECURITY CHECKPOINT: Confirm raw phone numbers are never persisted or logged *(runtime dump/log scan + static output-scan + PII-redacting logger + buffer wipe; live smoke-verified)*

### 4.4 Messaging Relay Service (Go)
- [x] Implement WebSocket connection management *(coder/websocket; first-frame protojson AuthRequest — token never in URL; 25s server ping / 10s pong timeout heartbeat; 1 MiB read limit; evict-on-reconnect registry)*
- [x] Implement ciphertext envelope routing (sender hash → recipient hash) *(sender_hash/sender_device_id always server-overridden from the authenticated token — spoofing impossible; opaque ciphertext routed byte-for-byte)*
- [x] Implement offline queue using Redis Streams (TTL 30 days) *(one `msg_queue:{blind_hash_id}` stream per recipient; XADD+XTRIM MINID retention in one pipeline; XDEL + purge-on-drain acks; verified with miniredis)*
- [x] Implement multi-device fan-out logic *(Hub: one blind_hash_id → many devices; fan-out to all live devices; sender's other devices get a sync copy minus the sending device; dead-peer eviction on write failure)*
- [x] Implement delivery acknowledgement and queue purge *(DeliveryAck(msg_id) → AckByMsgID → XDEL; stream deleted when drained; offline backlog drained to reconnecting devices)*
- [x] Implement Connection Request state machine *(pending → accepted/rejected/withdrawn/expired; CAS single-transition enforcement; actor authorization; idempotent create; lazy + periodic sweep expiry; NATS accept event with noop dev fallback)*
- [x] VERIFY: Write unit tests for WebSocket message routing *(real coder/websocket client over httptest: auth, spoof-block, multi-device fan-out, offline queue drain + ack purge, heartbeat survival, protocol violations)*
- [x] VERIFY: Write unit tests for offline queue TTL expiration *(XTRIM MINID drops entries older than the retention window, fresh entries survive — simulated ages)*
- [x] SECURITY CHECKPOINT: Confirm service never attempts to decrypt message bodies *(static scan bans all decryption primitives across the package; runtime test proves arbitrary ciphertext bytes survive the online + offline paths unmodified)*

### 4.5 PostgreSQL Schema & Migrations
- [x] Create PostgreSQL 16 database with extensions: postgis, pgcrypto, pg_stat_statements, uuid-ossp *(embedded Go migrations applied at service startup; all four extensions installed — live-verified on a real PostgreSQL)*
- [x] Define schema tables: users, usernames, devices, refresh_tokens, connection_requests *(0001_init up/down, transactional, advisory-locked runner with version tracking)*
- [x] Configure row-level security (RLS) for sensitive tables *(ENABLE + FORCE RLS on all 5 tables; per-table `app_full_access` policy scoped to civic_app; roles created NOLOGIN by the migration, activated with Vault-supplied passwords at bootstrap)*
- [x] Set up streaming replication to two standbys *(infrastructure/database: postgresql-primary.conf — wal_level=replica, synchronous_commit + synchronous_standby_names 'ANY 1 (civic_standby_1, civic_standby_2)'; postgresql-standby.conf + pg_basebackup bootstrap; pg_hba default-deny)*
- [x] Configure WAL archiving to MinIO for PITR *(archive_mode=on + wal-archive-to-minio.sh via wal-g; nightly base-backup CronJob infrastructure/security/postgres-wal-backup.yaml)*
- [x] VERIFY: Write unit tests for schema migrations *(forward + rollback live-verified incl. idempotent re-run and concurrent Migrate via advisory lock; static SQL checks for extensions/tables/RLS/pgcrypto run everywhere)*
- [x] VERIFY: Test RLS by attempting to query rows outside permission scope *(outsider role with full table grants sees 0 rows and cannot write; FORCE RLS blocks a non-superuser table owner; only civic_app sees its data — live-verified)*
- [x] SECURITY CHECKPOINT: Confirm PII columns use pgcrypto encryption at rest *(devices.public_key_enc = pgp_sym_encrypt bytea keyed by session GUC civic.enc_key; raw dump shows ciphertext only, wrong-key decrypt fails, right-key round-trips — live-verified)*

### 4.6 Redis Configuration
- [x] Deploy Redis Sentinel (3-node: 1 primary, 2 replicas, 3 sentinels) *(infrastructure/helm/redis: StatefulSet redis-0 primary + ordinals 1..N replicaof, redis-sentinel StatefulSet quorum 2, headless + sentinel services; live-verified with a real 6-container docker Sentinel cluster)*
- [x] Configure key namespaces: otp, refresh, revoked, msg_queue, karma, vote_buffer, analyst_load, rate *(internal/cache/namespaces.go registry: otp, otp_attempts, refresh, revoked, revoked_family, msg_queue, karma, vote_buffer, analyst_load, rate — validated key builders used by the identity OTP/refresh stores and the relay offline queue)*
- [x] Set up TTL policies for each namespace *(10m otp/otp_attempts, 30d refresh/revoked/revoked_family/msg_queue, 5m karma, 1m rate, no-TTL vote_buffer/analyst_load — constants + tests)*
- [x] Configure Redis persistence (AOF + RDB) *(appendonly yes + appendfsync everysec + RDB save points on a PVC; live-verified config get appendonly=yes + save points)*
- [x] VERIFY: Write integration tests for Redis operations *(env-gated live tests: pool starvation/recovery, TTL expiry, stream XTRIM MINID + purge-on-drain, Sentinel round-trip — all run against a real Redis 7 cluster)*
- [x] VERIFY: Test TTL expiration by setting keys and confirming deletion *(unit via miniredis FastForward + live against real Redis)*
- [x] SECURITY CHECKPOINT: Confirm no plaintext PII in Redis values *(validated key builders reject any PII-shaped suffix — raw E.164 phones, raw OTPs, emails, non-hex strings can never become keys; test suite proves rejection; keys strictly carry 64-hex blind hashes / SHA-256 digests)*

### 4.7 NATS JetStream Event Bus
- [x] Deploy NATS JetStream with durable streams *(internal/events JetStream client + infrastructure/helm/nats chart: `-js` + file storage on a PVC so CIVIC_EVENTS + durable consumers survive restarts; live-verified)*
- [x] Define topic schema for karma events and search sync *(internal/events/subjects.go registry: relay.connection.accepted, identity.user.registered, karma.updated, search.sync.requested — allowlist enforcement)*
- [x] Configure at-least-once delivery guarantees *(JetStream PUBACK-waiting Publish + durable push consumers with explicit acks and NAK-on-handler-error redelivery; nats.go auto-reconnect with logged reconnect/closed handlers)*
- [x] Implement consumer groups for karma service *(SubscribeDurable: explicit durable consumer creation + Bind so ack progress survives drains/restarts; ready for the karma/search services)*
- [x] VERIFY: Write integration tests for event publishing and consumption *(11 unit tests against an in-process nats-server: stream idempotency, pub/sub round-trip, NAK redelivery, restart resume with no event loss + no acked replay, concurrent durable-create race, Options storage/maxage fallback, PII rejection)*
- [x] VERIFY: Test durability by restarting NATS and confirming no event loss *(unit: server restart on the same store dir redelivers unacked events; live: scripts/verify_nats_live.sh restarts the docker broker and confirms the CIVIC_EVENTS stream + durable consumer survive — 8/8 checks)*
- [x] SECURITY CHECKPOINT: Confirm event payloads contain no plaintext PII *(ValidateSubject allowlist + logging.ContainsPII rejection on both subjects and payloads; E.164/email-shaped events rejected before the wire — proven by tests)*

### 4.8 HashiCorp Vault Integration
- [x] Deploy HashiCorp Vault via Helm chart *(deployed on a dedicated Hetzner node via `infrastructure/cloud-init-vault.tpl` (file storage, TLS listener, bootstrapped root token from Terraform) with External Secrets Operator syncing `infrastructure/eso/vault-secret-store.yaml` — the repo's established Vault deployment path)*
- [x] Configure transit secrets engine for encryption operations *(`TransitEncrypt`/`TransitDecrypt` helpers — base64 plaintext per the Vault transit API, `vault:v1:` ciphertext, live-verified against a real transit engine)*
- [x] Configure KV secrets engine for Argon2id salt and JWT signing keys *(KV v2 `ReadKV2` + `ReadKV2Meta` (version/created_time); live-verified against a real `civic-commons` kv-v2 mount holding `identity/argon2_salt` + `identity/jwt_rs256_public_key`)*
- [x] Implement Go client for Vault secrets fetching *(stdlib net/http, no SDK: `ReadKV2`/`ReadKV2Meta`, AppRole login, `LookupSelf`/`RenewSelf`, background renewal loop, `TransitEncrypt`/`TransitDecrypt`, `SecretCache` TTL-aware caching + rotation-detecting `Refresh`, `WipeBytes` zero-memory hygiene, `Connect` factory with fail-fast)*
- [x] Set up automatic secret rotation policies *(background `RunRenewal` re-logins and re-renews the client token; `SecretCache.Refresh` detects rotated secret versions so services re-read; buffer wipe on cache replacement)*
- [x] VERIFY: Write unit tests for Vault client operations *(httptest suite: AppRole success/403, KV v2 + metadata, transit round-trip + base64, SecretCache TTL/rotation, HTTP 401/403/404/500 sentinels, WipeBytes, Connect creds/renewal)*
- [x] VERIFY: Test secret rotation and confirm service picks up new values *(SecretCache refresh test proves a rotated value is picked up and reported as changed; live test refreshes against the real server)*
- [x] SECURITY CHECKPOINT: Confirm secrets are never written to application logs *(redacting logger now scrubs Vault token shapes (`hvs.`/`s.`), `X-Vault-Token` and `Authorization: Bearer` headers, and `X-Vault` request headers; production config refuses to run without Vault auth; `verify_vault_live.sh` checks the redaction tests live)*

---

## Phase 5: State Management & Sync Engine

### Objective
Implement the resilient background sync engine that bridges the local SQLite queue with the remote API Gateway, handling network volatility and ensuring data consistency.

### 5.1 Network State Detection
- [x] Implement `NetworkInfoProvider` using `connectivity_plus` *(data layer `ConnectivityNetworkInfoProvider` — `none`→offline, `mobile`→metered, wifi/ethernet/vpn/bluetooth/other→online; `currentStatus()` one-shot + `statusChanges` stream)*
- [x] Create network state enum: `online`, `offline`, `metered` *(`NetworkStatus` domain enum)*
- [x] Implement network state listener with debouncing (500ms) *(new `DebouncedNetworkInfoProvider` decorator — default 500ms quiet window, last-status-wins, flapping collapses to one emission; configurable duration, fakeAsync-tested)*
- [x] Create network-aware sync triggering logic *(`ReconnectionSyncTrigger` — fires exactly once per offline→online transition, never while offline; crash-safe fire-and-forget)*
- [x] VERIFY: Write unit tests for network state detection *(mapping tests + scripted-stream domain tests + debounce tests: window boundary, flapping collapse, window restart, custom duration)*
- [x] VERIFY: Write integration tests by toggling network and confirming state changes *(domain-level: scripted fake provider drives online/offline/metered transitions; platform-channel toggling is compile-verified — no device in this environment)*
- [x] SECURITY CHECKPOINT: Confirm network state is not used for fingerprinting *(state used solely to gate WHEN sync runs; never persisted, never leaves the device, never combined with user data — static checkpoint suite enforces no sqflite/secure_storage in lib/sync)*

### 5.2 Sync Worker Implementation
- [x] Create background isolate for sync operations using `workmanager` *(`WorkmanagerScheduler` — periodic 15-min + one-off sync tasks, ExistingWorkPolicy keep/replace, compile-verified; logic unit-tested, native scaffold lands with the app shell)*
- [x] Implement chunking logic: process queue items in batches of 10 *(`BatchChunker` — bounded batches, order-preserving, default max 10; used by `BackgroundSyncWorker`)*
- [x] Implement aggressive timeout limits: 10s per HTTP request *(worker wraps every `SyncSink.push` in a 10s `Future.timeout` — a hung connection is treated as a failure and retried, never stalls the drain; timeout configurable + unit-tested)*
- [x] Implement idempotency key generation and attachment to headers *(new `IdempotencyKeyGenerator` — RFC 4122 UUID v4 from `Random.secure()`, `Idempotency-Key` header constant; every queued mutation's id IS a UUID v4 idempotency key so retries dedupe server-side)*
- [x] Implement silent failure handling: increment retry count, update timestamp, no UI exception *(`markFailed` bumps retryCount; thrown/timeout sink errors never propagate to UI; crash recovery: `recoverInterrupted()` resets `in_progress`→`pending` at the start of every drain so killed runs are retried, never lost)*
- [x] VERIFY: Write unit tests for chunking logic *(8 chunker tests incl. 10+10+5, order preservation, cap enforcement)*
- [x] VERIFY: Write unit tests for idempotency key generation *(UUID v4 shape/version/variant, uniqueness ×1000, seeded-RNG determinism, header constant)*
- [x] SECURITY CHECKPOINT: Confirm sync worker never exposes plaintext payloads in logs *(no print/debugPrint in lib/sync, no raw transport imports, sink receives only sealed payloads — static + runtime checkpoint suite)*
- [x] EXTRA (hand-off scope): deterministic conflict-resolution hooks *(`ConflictResolutionPolicy` + `ServerAuthoritativeLastWriteWins` — server-ack beats local-only, newer timestamp wins, hash tiebreak so all devices converge; full conflict UI deferred to 5.5)*
- [x] EXTRA (hand-off scope): deterministic retry with exponential backoff + jitter — WIRED, not dead code *(`ExponentialBackoff.delayForRetryWithJitter` = equal jitter over `[base/2, base)` (guaranteed minimum, safe as a gate); schema v2 migration adds `sync_queue.last_attempt_at`; `getRetryable()` returns failed items whose backoff window has elapsed; the worker drains pending + retryable-failed together, so failed items are genuinely retried after their jittered window — never before base/2, always by base, window grows with retryCount)*

### 5.3 Idempotency Enforcement
- [x] Implement UUID v4 idempotency key generation *(Task 5.2 client-side: `IdempotencyKeyGenerator` — RFC 4122 UUID v4 from `Random.secure()`; every queued mutation's id IS a UUID v4 key)*
- [x] Attach `Idempotency-Key` header to all mutation requests *(Task 5.2: `Idempotency-Key: <item.id>` attached by the sync worker's transport so retries dedupe server-side)*
- [x] Implement server-side idempotency key tracking in Redis (TTL 24 hours) *(new `internal/idempotency` package — Redis SETNX claim / GET / SET complete / DEL clear against the validated `idempotency:` namespace; `IDEMPOTENCY_TTL` default 24h; keys are actor-scoped `idempotency:{blind_hash_id}:{uuid}`)*
- [x] Create idempotency conflict resolution logic *(middleware on the relay's POST mutation routes inside auth: missing header = passthrough, malformed = 400, claim-winner processes + caches the 2xx response (64 KiB cap), concurrent in-flight = 409, completed = cached replay with `Idempotent-Replayed` header, handler failure = key cleared so the retry reprocesses)*
- [x] VERIFY: Write unit tests for idempotency key generation *(client: UUID v4 shape/version/variant + uniqueness ×1000; server: `cache.IdempotencyKey`/`IdempotencyKeyScoped` validation + PII-shaped-suffix rejection)*
- [x] VERIFY: Write integration tests by sending duplicate requests and confirming deduplication *(relay HTTP integration: same key + actor → single side effect then cached replay; concurrent race → exactly one 201; cross-actor same key → NO dedup)*
- [x] SECURITY CHECKPOINT: Confirm idempotency keys are random and not predictable *(UUID v4 from a crypto-secure RNG client-side; the server key builder strictly validates UUID v4 shape and rejects PII-shaped suffixes before any Redis write — raw phones/OTPs/emails can never become keys; actor scoping prevents cross-user replay of cached responses)*

### 5.4 Sync Status UI Integration
- [x] Create `SyncStatusBar` widget showing: LIVE, CACHED, QUEUED, OFFLINE *(`lib/state/ui/sync_status_bar.dart` — compact status chip with per-state color/icon: LIVE=green/cloud_done, CACHED=amber/cloud_queue, QUEUED=blue/cloud_upload, OFFLINE=grey/cloud_off)*
- [x] Implement tap-to-expand showing last-sync timestamp and queue count *(InkWell toggle expands an `AnimatedSize` panel with "Last synced: …" (`formatLastSync`: Never/Just now/Xm/Xh/Xd ago/date) and "N pending mutation(s)")*
- [x] Bind sync status to BLoC state stream *(`StreamBuilder` over `SyncStatusBloc.state` — the widget consumes ONLY the BLoC interface; no repository/DB/network access in the widget tree)*
- [x] Implement visual feedback for sync operations (subtle progress indicator) *(14px `CircularProgressIndicator` rendered while `SyncStatusState.isSyncing` — driven by the bloc's in-progress queue-item derivation)*
- [x] VERIFY: Write widget tests for SyncStatusBar states *(22 widget tests: all four states + empty-before-emit, badge show/update/drain, LIVE↔OFFLINE transitions, progress indicator show/hide, tap-expand/collapse + singular wording + Never, `formatLastSync` units, security text-shape checks)*
- [x] VERIFY: Write integration tests by triggering sync and confirming UI updates *(2 integration tests: real `ReconnectionSyncTrigger` + `BackgroundSyncWorker` + `LocalSyncStatusBloc` driving the bar — reconnect fires a real drain QUEUED→LIVE, and a gated sink proves the in-flight progress indicator; async teardown via `runAsync`)*
- [x] SECURITY CHECKPOINT: Confirm sync status never exposes sensitive data *(state contract extended additively with non-PII `lastSyncAt` timestamp + `isSyncing` boolean only; runtime widget-tree scan asserts no phone/email/hvs./64-hex/JWT-shaped text; static scan proves no direct data-layer access, no prints, fixed enum labels only; 5 security tests)*

### 5.5 Conflict Resolution Logic
- [x] Implement last-write-wins for simple fields *(ServerAuthoritativeLastWriteWins refined: authority → timestamp → author-hash tiebreak)*
- [x] Implement merge logic for nested structures (e.g., karma scores) *(MaxMergePolicy — commutative/idempotent/associative on non-PII numeric aggregates)*
- [x] Create conflict detection by comparing local vs remote timestamps *(SyncPushOutcome carries the server's MutationVersion into the worker/repo loops)*
- [x] Implement user-facing conflict resolution UI for critical data *(ConflictResolutionBanner — fixed non-PII outcome labels; app-shell wiring deferred to Phase 6)*
- [x] VERIFY: Write unit tests for conflict resolution algorithms
- [x] VERIFY: Write integration tests by simulating conflicting edits
- [x] SECURITY CHECKPOINT: Confirm conflict resolution never exposes raw data to logs

### 5.6 Offline Queue Persistence
- [x] Implement queue persistence across app restarts *(durable SQLCipher rows with exact serialization/deserialization bounds; `recoverInterrupted()` resets crash-stranded in_progress items to pending on cold start — nothing is lost)*
- [x] Create queue backup/restore mechanism *(`SyncQueueBackup`: sealed-only JSON envelope codec — versioned, fully validated before any insert, idempotent restore that can never duplicate a mutation)*
- [x] Implement queue size limits (max 1000 items, FIFO eviction) *(cap enforced on insert; OLDEST non-in-flight items evicted, in-flight protected, just-inserted item guaranteed to survive by construction)*
- [x] Create queue cleanup for expired items (30 days) *(`purgeExpired` strict boundary — exactly-30-day-old items survive; wired into the worker before every drain so stale mutations are never pushed)*
- [x] VERIFY: Write unit tests for queue persistence
- [x] VERIFY: Write integration tests by restarting app during sync
- [x] SECURITY CHECKPOINT: Confirm queued data remains encrypted at rest *(AES-256-GCM sealed before storage, verified across restart/backup/restore paths)*

---

## Phase 6: Pillar 1 — The Vault (Secure Messaging)

### Objective
Implement the Vault pillar with end-to-end encrypted messaging, connection requests, and zero-cloud-footprint architecture.

### 6.1 Vault UI Foundation
- [x] Create `VaultMasthead` component with classified document aesthetic *(Vault Blue #1A3D6B strip, lock glyph, `THE VAULT` tracked wordmark, `[CLASSIFIED]` stamp, black pseudo-redaction bar; DESIGN §2.2/§6.2)*
- [x] Implement conversation list screen with ciphertext previews *(preview is ALWAYS the fixed `[end-to-end encrypted]` label — never a plaintext snippet, shoulder-surfing protection; peers rendered only via non-PII `formatPeerHandle`)*
- [x] Create conversation detail screen with message bubbles *(received = white + 3dp Vault Blue left bar, sent = Vault Blue panel; ✓/✓✓ receipts, amber queued indicator, `Expires` marker; body is a fixed E2EE placeholder until 6.3 wires decryption)*
- [x] Implement connection request queue UI *(collapsible `PENDING REQUESTS (N)` section with Accept buttons — read-only when the accept flow is not yet wired, inbox never invisible)*
- [x] Apply `FLAG_SECURE` wrapper to all Vault screens *(both screens wrap in `SecureScreenWrapper` — verified statically + runtime enable-on-mount)*
- [x] VERIFY: Write widget tests for VaultMasthead rendering
- [x] VERIFY: Write integration tests for conversation list navigation *(real `LocalConversationBloc` + `LocalDataStreamController` + fake repo end-to-end)*
- [x] SECURITY CHECKPOINT: Confirm FLAG_SECURE is active on all Vault screens

### 6.2 Connection Request Flow
- [x] Implement username search via API Gateway *(new auth-required `GET /v1/identity/username/{username}` — resolves a claimed username → owner blind hash; policy-validated (invalid formats never resolve), 404 for unknown/released usernames (the 30-day cooldown is a privacy boundary), response carries only `{username, blind_hash_id}`; 5 Go tests incl. no-phone-in-response/logs)*
- [x] Create connection request sending logic *(local-first `LocalConnectionRequestRepository`: send/accept/reject/withdraw persist immediately + enqueue AES-GCM-sealed sync envelopes; blind-hash-only targets — a raw phone is rejected before it can reach storage or the queue; idempotent while pending)*
- [x] Implement connection request receiving and approval UI *(the Task 6.1 `PENDING REQUESTS (N)` queue is now BLoC-driven — `LocalConnectionRequestsBloc` + repository feed `VaultPendingRequestsSection` with wired Accept; new FLAG_SECURE `UsernameSearchSheet` for finding peers by public username; conversation tiles resolve remembered `@username`s)*
- [x] Create Connection Request state machine in local database *(`connection_requests` row codecs + single-transition CAS status rules mirroring the relay — terminal states immutable)*
- [ ] Implement cryptographic key exchange on approval *(deferred to Task 6.3 with session establishment)*
- [x] VERIFY: Write unit tests for connection request state transitions
- [ ] VERIFY: Write integration tests for key exchange on approval *(deferred to Task 6.3)*
- [x] SECURITY CHECKPOINT: Confirm connection requests never expose phone numbers *(blind-hash-only targets rejected pre-storage; sync envelopes carry UUID + blind hashes + status only; UI renders `formatPeerHandle` / public `@username` only — runtime widget-tree scans)*

### 6.3 Message Encryption & Decryption
- [x] Implement client-side message encryption using Signal Protocol *(X3DH session establishment wired into the connection-approval hook deferred in 6.2; Double Ratchet encrypt/decrypt orchestrated by `SessionManager` keyed by blind hash; `MessageCipher` port seals/opens bodies in the message BLoC)*
- [x] Create message bubble UI with sent/received states *(6.1 styling + explicit `MessageDirection` field superseding the delivered-heuristic `MessageSideResolver`)*
- [ ] Implement read receipt logic (✓ sent, ✓✓ delivered, ✓✓✓ read) *(✓/✓✓ rendered from 6.1; ✓✓✓ read-receipt tracking deferred — needs the server relay's read-ack plumbing)*
- [ ] Create message expiration logic (TTL-based deletion) *(Expires marker rendered; background TTL deletion deferred)*
- [x] Implement message queueing for offline send *(`MessageBloc.send` encrypts → `LocalMessageRepository.create` persists locally as sent/undelivered + enqueues the sealed payload into the encrypted sync queue)*
- [x] VERIFY: Write unit tests for message encryption/decryption *(session manager 9, session establisher + message cipher 7, bloc decrypt-on-emit + send 9, bubble content rendering 3, composer 5)*
- [x] VERIFY: Write integration tests for offline message queuing *(send round-trip: encrypt → persist → queue → republish with decrypted content)*
- [x] SECURITY CHECKPOINT: Confirm message content is never logged plaintext *(no prints in lib/state; state carries only decrypted `content` for rendering — never ciphertext; undecryptable messages fall back to the fixed placeholder; send failures are swallowed, never logged)*

### 6.4 WebSocket Message Relay
- [x] Implement WebSocket client for real-time message delivery *(new `lib/relay/` tree — `RelayClient` orchestrates first-frame JWT auth, read loop, envelope dispatch + auto-ack, reconnect with the shared Task 5.2 `ExponentialBackoff`, and dead-connection detection; `RelaySocket`/`RelaySocketConnector` ports with `WebSocketRelaySocket` over `web_socket_channel` ^2.4.0)*
- [x] Create message envelope parsing logic *(`RelayEnvelope` + sealed `RelayFrame` codec mirroring the Go relay's protojson `UseProtoNames` wire exactly — oneof members auth/auth_ack/envelope/ack/error, snake_case fields, base64 ciphertext; `DiscardUnknown` tolerance, UUID-v4 msg id + 64-hex blind-hash validation at the port boundary)*
- [x] Implement heartbeat/ping-pong for connection health *(transport-level: `pingInterval: 20s` on the channel so dart:io closes when the relay stops ponging — the correct detector because the relay's 25s pings are protocol control frames that never surface as data frames; `RelayHeartbeat` data-frame watchdog retained for sockets without transport liveness, gated by `hasTransportHeartbeat`)*
- [x] Create reconnection logic with exponential backoff *(shared `ExponentialBackoff.delayForRetryWithJitter`; generation-guarded sessions so stale callbacks are inert; a drop during the auth handshake before any auth_ack is TRANSIENT — only an explicit `auth_ack:false` is terminal, and the post-rejection close is never retried)*
- [x] Implement dummy traffic for obfuscation (opt-in) *(`DummyTrafficGenerator` — scheduled UUID-v4 keepalive envelopes via an injectable `send`, clock/timer-injectable, non-PII)*
- [x] VERIFY: Write integration tests for WebSocket connection lifecycle *(real `dart:io` WebSocket server + `IOWebSocketChannel`: first-frame auth asserted with empty query params (JWT never in URL), envelope delivery + auto-ack round-trip, client→server envelope, remote-close reconnect re-authenticates, transport-heartbeat capability pinned)*
- [x] VERIFY: Write unit tests for heartbeat timeout handling *(fake_async `RelayHeartbeat` watchdog tests + RelayClient stale-watchdog tear-down/reconnect, transport-heartbeat-skips-watchdog, pre-auth-drop-reconnects, rejection-close-terminal)*
- [x] SECURITY CHECKPOINT: Confirm WebSocket authentication uses JWT in body, not URL *(token lives only in the first auth frame body — asserted in unit tests (URL contains no token/query) and in the live-socket integration test (server asserts empty upgrade query params); ciphertext is opaque and never logged; no print in lib/relay; PII/64-hex shaped values rejected pre-wire; static + runtime security checkpoint suite)*

### 6.5 Multi-Device Pairing
- [x] Implement QR code generation for device pairing *(new `lib/pairing/` tree: `PairingPayload` strict zero-PII QR codec (civic-commons://pair URI, 64-hex blind hash + UUID v4 + one-time secret + PUBLIC keys only), `PairingSecretGenerator` (32-byte CSPRNG base64url, 5-min window), `QrMatrix` value object + `QrEncoder`/`QrScanner` ports, `qr_codec_impl.dart` wrapping the pure-Dart `qr` package (medium ECC), `DevicePairingService` orchestrator — PRIMARY signs the signed prekey with the REAL Ed25519 identity key; NEW DEVICE cryptographically verifies that signature at the authorize gate before any session/registration, plus one-time-secret single-use consumption)*
- [x] Create QR scanning logic for new device authorization *(`scanAndAuthorize`/`authorizePayloadText` — strict decode → expiry check → account-match check → Ed25519 signature verification → X3DH initiator session → registry registration; camera `QrScanner` port documented for the device-camera path, manual code entry fully implemented + tested via FLAG_SECURE `PairingScanSheet`)*
- [x] Implement key transfer via QR (not cloud sync) *(payload carries ONLY public keys + blind hash + one-time secret; private keys never leave `SecureKeyStorage`; no backup/upload/sync identifiers anywhere in `lib/pairing` — enforced by the checkpoint test with word-boundary regexes over code lines)*
- [x] Create device management UI (list linked devices, revoke) *(FLAG_SECURE `DeviceManagementSheet`: `LinkedDevicesBloc` list rendered ONLY via `formatDeviceHandle` (never raw UUIDs/keys), per-device Revoke → registry row marked revoked + X3DH session deleted, `DevicePairingBloc` QR panel via `PairingQrView` (CustomPaint matrix — payload text never rendered)*
- [x] VERIFY: Write integration tests for QR-based pairing *(widget tests: management sheet renders/revokes/QR-panel, scan sheet submit/error/FLAG_SECURE-on-mount; service tests: full authorize lifecycle incl. session established + registry registered, expiry, wrong-account, PII-shaped rejection, revocation + session deletion, active-list projection)*
- [x] VERIFY: Write unit tests for device revocation *(revokeDevice idempotent, unknown-device no-op, revoked rows excluded from the active list, session cleanup verified)*
- [x] SECURITY CHECKPOINT: Confirm device pairing never uses cloud backup *(static scans: zero cloud/sync/upload identifiers, zero print/debugPrint, zero phone/e-mail literals, payload codec never serializes private keys, service depends only on ports; runtime: QR signature is REAL Ed25519 and verifies (tampered spk/ik rejected), one-time secret single-use (replay rejected), `SecureStorageIdentityKeySource` tested directly — no private key escapes)*

### 6.6 Duress PIN Integration
- [x] Integrate duress PIN flow into Vault unlock *(new `VaultUnlockBloc`/`VaultUnlockState` + `LocalVaultUnlockBloc` wrapping the Phase 2.5 `DuressService`: one PIN prompt for BOTH PINs — `unlock(pin)` returns the opened `UnlockResult` (real vs decoy vault) only to the routing callback, the state stream never reveals which vault was opened; generic failure identical for wrong/empty/near-miss PINs; FLAG_SECURE `VaultUnlockScreen` with an obscured numeric PIN field, spinner, single generic error, and a setup path when unregistered)*
- [x] Create decoy Vault UI (visually identical, empty) *(`DecoyVaultScreen`: same `VaultMasthead`, same CONVERSATIONS header, and the SHARED `VaultEmptyState` widget — extracted so the decoy is byte-identical to a freshly-registered real vault; takes NO data inputs and references no bloc/repository/entity types; FLAG_SECURE wrapped so it is not distinguishable by its security guard either; proven by a runtime test comparing the decoy's rendered text to the real empty list's)*
- [x] Implement duress PIN detection and database switching *(pure decryption-based selection via `DuressService` — the real PIN's derived key opens `vault.db`, the duress PIN's opens `vault_decoy.db`; the real service never stores which PIN is real; integration tests prove real records persist in the real vault and are INVISIBLE through the decoy result)*
- [x] Create duress PIN setup flow during onboarding *(`DuressSetupBloc`/`DuressSetupState` + `LocalDuressSetupBloc` + FLAG_SECURE `DuressPinSetupSheet`: the ONE screen that labels the two obscured PIN fields; identical/empty/duplicate registrations all map to a single generic error; PINs wiped from the controllers after every attempt)*
- [x] VERIFY: Write unit tests for duress PIN database switching *(bloc tests: real PIN → `VaultKind.real` + real DB handle, duress PIN → `VaultKind.decoy` + decoy DB handle with IDENTICAL state transitions, real-vs-decoy record isolation, wrong/empty/near-miss PINs → same generic failure, failing-service → generic failure not crash)*
- [x] VERIFY: Write integration tests for decoy Vault rendering *(widget tests: decoy renders masthead+CONVERSATIONS+shared empty state; rendered-text comparison to the real empty list is IDENTICAL; no rows/previews/handles; setup sheet registers valid PINs and rejects identical ones; unlock screen routes real→real and duress→decoy with byte-identical failure UI)*
- [x] SECURITY CHECKPOINT: Confirm duress PIN is indistinguishable from real PIN *(static scans: unlock screen code never references real/duress/decoy/VaultKind and never inspects the result kind, state models carry no key/DB fields, no print/debugPrint, no PII literals; runtime: near-real and near-duress PINs produce byte-identical failure UI, decoy text ≡ real-empty text; integration: persisted vault bytes contain no real/duress/decoy indicator — the app never stores which PIN is real)*

---

## Phase 7: Pillar 2 — The Daily Ledger (Hyperlocal News)

### Objective
Implement the Ledger pillar with pin-code-scoped civic news, peer review moderation, and dynamic radius expansion for low-density areas.

### 7.1 Ledger UI Foundation
- [ ] Create `LedgerMasthead` component with newspaper aesthetic
- [ ] Implement feed screen with pin-code scoping
- [ ] Create post detail screen with voting and comments
- [ ] Implement compose post screen with category selection
- [ ] Create `CategoryChip` component for post tagging
- [ ] VERIFY: Write widget tests for LedgerMasthead rendering
- [ ] VERIFY: Write integration tests for feed navigation
- [ ] SECURITY CHECKPOINT: Confirm feed renders from local cache first

### 7.2 Geographic Clustering Implementation
- [ ] Implement pin-code resolution using `geolocator`
- [ ] Create PostGIS queries for constituency/district lookup
- [ ] Implement pin-code feed filtering in local database
- [ ] Create "Explore Nearby" radius control UI
- [ ] VERIFY: Write unit tests for pin-code validation
- [ ] VERIFY: Write integration tests for geographic resolution
- [ ] SECURITY CHECKPOINT: Confirm location data is not used for fingerprinting

### 7.3 Dynamic Radius UI (Skill: dynamic-radius-ui)
- [ ] Implement threshold check: query local DB for posts in last 7 days
- [ ] Create radius expansion logic (pin code → constituency → district)
- [ ] Implement `NearbyBadgeWidget` for expanded results
- [ ] Create seamless blending of local and nearby results
- [ ] VERIFY: Write unit tests for threshold check logic
- [ ] VERIFY: Write integration tests for radius expansion
- [ ] SECURITY CHECKPOINT: Confirm expanded results are clearly marked

### 7.4 Post Creation & Queuing
- [ ] Implement post creation form with category selection
- [ ] Create local draft storage using Hive
- [ ] Implement post encryption before queuing
- [ ] Create sync queue insertion for new posts
- [ ] VERIFY: Write unit tests for post creation flow
- [ ] VERIFY: Write integration tests for offline post queuing
- [ ] SECURITY CHECKPOINT: Confirm posts are encrypted before sync

### 7.5 Voting System with Karma Weighting
- [ ] Implement vote recording with karma-weighted sub-linear scoring
- [ ] Create vote caching in Redis with batch flush to PostgreSQL
- [ ] Implement vote UI with upvote/downvote buttons
- [ ] Create vote sync logic for offline votes
- [ ] VERIFY: Write unit tests for karma-weighted vote calculation
- [ ] VERIFY: Write integration tests for offline vote queuing
- [ ] SECURITY CHECKPOINT: Confirm vote weights are calculated client-side

### 7.6 Peer Review Gate
- [ ] Implement Shadow Queue for new accounts (<96 hours)
- [ ] Create karma threshold check for fast-track publishing
- [ ] Implement reviewer assignment (3 random high-karma users)
- [ ] Create review UI with approve/reject buttons
- [ ] Implement moderation flag handling
- [ ] VERIFY: Write unit tests for Shadow Queue logic
- [ ] VERIFY: Write integration tests for reviewer assignment
- [ ] SECURITY CHECKPOINT: Confirm reviewer identities are blinded

---

## Phase 8: Pillar 3 — The War Room (OSINT Cyber Defense)

### Objective
Implement the War Room pillar with encrypted evidence handling, severity scoring, and analyst collaboration with PII redaction.

### 8.1 War Room UI Foundation
- [ ] Create `WarRoomMasthead` component with dossier aesthetic
- [ ] Implement case list screen with severity bands
- [ ] Create case detail/investigation view
- [ ] Implement file new case intake flow
- [ ] Apply `FLAG_SECURE` wrapper to all War Room screens
- [ ] VERIFY: Write widget tests for WarRoomMasthead rendering
- [ ] VERIFY: Write integration tests for case navigation
- [ ] SECURITY CHECKPOINT: Confirm FLAG_SECURE is active on all War Room screens

### 8.2 Encrypted Evidence Upload
- [ ] Implement client-side evidence encryption (AES-256-GCM)
- [ ] Create DEK (Data Encryption Key) generation per evidence item
- ] Implement DEK wrapping with victim's and analysts' public keys
- [ ] Create MinIO upload via presigned URLs
- [ ] Implement evidence metadata storage (encrypted)
- [ ] VERIFY: Write unit tests for evidence encryption/decryption
- [ ] VERIFY: Write integration tests for MinIO upload
- [ ] SECURITY CHECKPOINT: Confirm evidence never decrypts server-side

### 8.3 PII Redaction Pipeline (Skill: local-pii-redaction)
- [ ] Implement deterministic regex filters for phone numbers, emails, government IDs
- [ ] Create local Gemma model integration for contextual PII detection
- [ ] Implement redaction prompt template from resources
- [ ] Create memory wipe logic after encryption (nullify plaintext variables)
- [ ] VERIFY: Write unit tests for regex PII detection
- [ ] VERIFY: Write integration tests for Gemma model redaction
- [ ] SECURITY CHECKPOINT: Confirm plaintext is wiped immediately after encryption

### 8.4 Severity Scoring System
- [ ] Implement keyword-based severity scoring (CRITICAL, HIGH, MEDIUM, LOW)
- [ ] Create severity band UI component
- [ ] Implement SLA tracking based on severity
- [ ] Create severity override UI for human review
- [ ] VERIFY: Write unit tests for severity scoring logic
- [ ] VERIFY: Write integration tests for SLA tracking
- [ ] SECURITY CHECKPOINT: Confirm severity scoring is deterministic

### 8.5 Analyst Assignment & Collaboration
- [ ] Implement analyst vetting gauntlet (CTF-style sandbox)
- [ ] Create blind review enforcement (analysts cannot see each other's notes)
- [ ] Implement case assignment logic (skill-tag matched)
- [ ] Create analyst load tracking (case cap enforcement)
- [ ] VERIFY: Write unit tests for analyst assignment logic
- [ ] VERIFY: Write integration tests for blind review enforcement
- [ ] SECURITY CHECKPOINT: Confirm analyst identities are blinded to victims

### 8.6 Chain of Custody Logging
- [ ] Implement append-only custody log in PostgreSQL
- [ ] Create custody log viewer UI
- [ ] Implement HMAC signing for Verified Intel Report
- [ ] Create legal-aid handoff webhook integration
- [ ] VERIFY: Write unit tests for custody log append-only property
- [ ] VERIFY: Write integration tests for HMAC signing
- [ ] SECURITY CHECKPOINT: Confirm custody log is immutable

### 8.7 Trauma-Informed Intake UX
- [ ] Implement voice-note evidence capture using `record` and `just_audio`
- [ ] Create optional voice-to-text transcription
- [ ] Implement consent checkpoint UI at each stage
- [ ] Create one-tap case pause/withdraw option
- [ ] VERIFY: Write widget tests for voice input component
- [ ] VERIFY: Write integration tests for voice-to-text flow
- [ ] SECURITY CHECKPOINT: Confirm voice data is encrypted immediately after capture

---

## Phase 9: Pillar 4 — The Academy (Open Education)

### Objective
Implement the Academy pillar with structured syllabus tree, offline caching, and distraction-free video delivery.

### 9.1 Academy UI Foundation
- [ ] Create `AcademyMasthead` component with textbook aesthetic
- [ ] Implement syllabus tree navigation screen
- [ ] Create module view with video player and sandbox
- [ ] Implement progress tracking UI
- [ ] VERIFY: Write widget tests for AcademyMasthead rendering
- [ ] VERIFY: Write integration tests for syllabus navigation
- [ ] SECURITY CHECKPOINT: Confirm video player uses privacy-enhanced embed mode

### 9.2 Syllabus Tree Implementation
- [ ] Implement hierarchical syllabus data structure (Domain → Category → Subject → Module)
- [ ] Create syllabus tree UI with expand/collapse
- [ ] Implement locale tagging for regional variants
- [ ] Create syllabus search using Meilisearch
- [ ] VERIFY: Write unit tests for syllabus tree traversal
- [ ] VERIFY: Write integration tests for syllabus search
- [ ] SECURITY CHECKPOINT: Confirm syllabus data is served from local cache

### 9.3 Video Room with Privacy-Enhanced Embeds
- [ ] Implement YouTube embed with privacy-enhanced mode (`youtube-nocookie.com`)
- [ ] Strip all recommendations, autoplay, and Shorts
- [ ] Implement HLS player for proprietary content (Cloudflare R2/Bunny.net)
- [ ] Create adaptive bitrate streaming (ABR) for low-bandwidth
- [ ] VERIFY: Write integration tests for YouTube embed rendering
- [ ] VERIFY: Write integration tests for HLS playback
- [ ] SECURITY CHECKPOINT: Confirm no recommendation sidebars in video player

### 9.4 Offline Module Caching
- [ ] Implement module manifest generation (list of assets with sizes)
- [ ] Create download-for-offline flow with storage warning
- [ ] Implement background download using WorkManager
- [ ] Create offline content playback logic
- [ ] VERIFY: Write integration tests for module download
- [ ] VERIFY: Write integration tests for offline playback
- [ ] SECURITY CHECKPOINT: Confirm cached content is stored in encrypted partition

### 9.5 Sandbox Wiki System
- [ ] Implement Markdown editor for Sandbox contributions
- [ ] Create version control system (diff + revert)
- [ ] Implement attributed-but-pseudonymous authorship
- [ ] Create Sandbox sync logic for offline edits
- [ ] VERIFY: Write unit tests for Markdown version control
- [ ] VERIFY: Write integration tests for offline edit queuing
- [ ] SECURITY CHECKPOINT: Confirm Sandbox edits are encrypted before sync

### 9.6 Cross-Pillar Study Group Matching
- [ ] Implement pin-code-based learner matching
- [ ] Create study group invitation flow via Vault
- [ ] Implement group chat using Vault messaging
- [ ] Create study group progress tracking
- [ ] VERIFY: Write integration tests for study group matching
- [ ] VERIFY: Write integration tests for group chat
- [ ] SECURITY CHECKPOINT: Confirm study group data uses Vault E2EE

---

## Phase 10: Cross-Pillar Systems

### Objective
Implement the shared systems that tie all pillars together: unified identity, karma engine, and notification system.

### 10.1 Unified Identity Layer
- [ ] Implement blind-hash ID sharing across all pillars
- [ ] Create identity service with minimum claim extraction
- [ ] Implement pillar-specific permission checks
- [ ] Create identity verification UI (one-time during onboarding)
- [ ] VERIFY: Write unit tests for blind-hash ID generation
- [ ] VERIFY: Write integration tests for cross-pillar identity sharing
- [ ] SECURITY CHECKPOINT: Confirm no pillar stores full user profile

### 10.2 Civic Karma Engine
- [ ] Implement karma event consumption from NATS
- [ ] Create karma calculation logic with sub-linear voting weight
- [ ] Implement karma gates (threshold checks for privileges)
- [ ] Create monthly decay job (-2% for inactive accounts)
- [ ] Implement anomaly detection for lockstep voting
- [ ] VERIFY: Write unit tests for karma calculation
- [ ] VERIFY: Write integration tests for karma gate enforcement
- [ ] SECURITY CHECKPOINT: Confirm karma events are append-only and auditable

### 10.3 Karma Badge UI
- [ ] Implement `KarmaBadge` component with tier indicators
- [ ] Create karma dashboard screen
- [ ] Implement karma level-up animation
- [ ] Create karma history viewer
- [ ] VERIFY: Write widget tests for KarmaBadge rendering
- [ ] VERIFY: Write integration tests for karma level-up flow
- [ ] SECURITY CHECKPOINT: Confirm karma scores are not used for fingerprinting

### 10.4 Notification System
- [ ] Implement push notification service (Firebase Cloud Messaging or self-hosted)
- [ ] Create notification types: karma events, case assignments, Ledger review requests
- [ ] Implement notification preferences UI
- [ ] Create notification history viewer
- [ ] VERIFY: Write integration tests for push notification delivery
- [ ] VERIFY: Write unit tests for notification type filtering
- [ ] SECURITY CHECKPOINT: Confirm notifications contain no PII in payload

### 10.5 Transparency Log
- [ ] Implement append-only transparency log for moderation actions
- [ ] Create transparency log viewer UI per pin-code board
- [ ] Implement government request logging (PII stripped)
- [ ] Create log verification using cryptographic hashes
- [ ] VERIFY: Write unit tests for append-only log property
- [ ] VERIFY: Write integration tests for log verification
- [ ] SECURITY CHECKPOINT: Confirm transparency log is publicly readable but PII-free

---

## Phase 11: Security Hardening & Compliance

### Objective
Implement comprehensive security measures, compliance features, and audit mechanisms to meet regulatory requirements and protect user data.

### 11.1 DPDP Consent Implementation
- [ ] Create DPDP consent flow during onboarding
- [ ] Implement consent versioning and tracking
- [ ] Create consent withdrawal UI
- [ ] Implement data deletion on consent withdrawal
- [ ] VERIFY: Write unit tests for consent tracking
- [ ] VERIFY: Write integration tests for data deletion on withdrawal
- [ ] SECURITY CHECKPOINT: Confirm consent is obtained before any data processing

### 11.2 Audit Logging System
- [ ] Implement comprehensive audit log for all sensitive operations
- [ ] Create audit log viewer for admin users (two-person authorization)
- [ ] Implement audit log export functionality
- [ ] Create audit log retention policy (7 years)
- [ ] VERIFY: Write unit tests for audit log capture
- [ ] VERIFY: Write integration tests for audit log export
- [ ] SECURITY CHECKPOINT: Confirm audit logs are tamper-evident

### 11.3 Rate Limiting & Abuse Prevention
- [ ] Implement per-blind-hash_id rate limiting in Kong
- [ ] Create abuse detection logic for anomalous patterns
- [ ] Implement CAPTCHA challenge for suspicious activity
- [ ] Create abuse reporting UI for users
- [ ] VERIFY: Write integration tests for rate limiting
- [ ] VERIFY: Write unit tests for abuse detection logic
- [ ] SECURITY CHECKPOINT: Confirm rate limiting does not use IP addresses

### 11.4 Security Audit & Penetration Testing
- [ ] Conduct automated security scanning using `trivy` and `grype`
- [ ] Perform dependency vulnerability scanning
- [ ] Conduct manual penetration testing on API endpoints
- [ ] Implement security fixes from audit findings
- [ ] VERIFY: Run automated security scanners and confirm zero critical vulnerabilities
- [ ] VERIFY: Document and remediate all penetration test findings
- [ ] SECURITY CHECKPOINT: Confirm all critical vulnerabilities are remediated before deployment

### 11.5 Compliance Documentation
- [ ] Create data processing agreement templates
- [ ] Implement privacy policy versioning
- [ ] Create security whitepaper for public transparency
- ] Implement bug bounty program documentation
- [ ] VERIFY: Review legal documentation with compliance team
- [ ] VERIFY: Publish security whitepaper for transparency
- [ ] SECURITY CHECKPOINT: Confirm all documentation is accurate and up-to-date

---

## Phase 12: Performance Optimization & Scalability

### Objective
Optimize application performance for low-end devices and implement scalability measures for growth.

### 12.1 Client-Side Performance Optimization
- [ ] Implement lazy loading for images and videos
- [ ] Create image compression and resizing logic
- [ ] Implement code splitting for Flutter (defer loading of less-used pillars)
- [ ] Optimize app startup time (target <600ms cold start)
- [ ] VERIFY: Measure app startup time on budget Android device
- [ ] VERIFY: Profile memory usage and confirm no leaks
- [ ] SECURITY CHECKPOINT: Confirm optimizations do not compromise security

### 12.2 Database Performance Optimization
- [ ] Implement database connection pooling
- [ ] Create database query optimization (indexes, query plans)
- [ ] Implement read replicas for read-heavy operations
- [ ] Create database caching layer (Redis)
- [ ] VERIFY: Run database load tests and confirm <100ms query latency
- [ ] VERIFY: Monitor database connection pool utilization
- [ ] SECURITY CHECKPOINT: Confirm read replicas do not expose sensitive data

### 12.3 CDN & Content Delivery Optimization
- [ ] Configure Cloudflare CDN for static assets
- [ ] Implement Bunny.net CDN for video delivery
- [ ] Create edge caching rules for API responses
- [ ] Implement image optimization at edge
- [ ] VERIFY: Measure CDN cache hit ratio and confirm >80%
- [ ] VERIFY: Test video delivery with adaptive bitrate
- [ ] SECURITY CHECKPOINT: Confirm CDN does not cache sensitive data

### 12.4 Horizontal Scaling Preparation
- [ ] Implement Kubernetes horizontal pod autoscaling
- [ ] Create database sharding strategy (pin-code prefix-based)
- [ ] Implement service mesh for inter-service communication (optional)
- [ ] Create load testing scenarios for scale testing
- [ ] VERIFY: Run load tests with 10,000 concurrent users
- [ ] VERIFY: Monitor autoscaling behavior under load
- [ ] SECURITY CHECKPOINT: Confirm scaling does not expose sensitive data

---

## Phase 13: Testing & Quality Assurance

### Objective
Implement comprehensive testing strategy covering unit tests, integration tests, E2E tests, and security testing.

### 13.1 Unit Test Coverage
- [ ] Achieve 80%+ code coverage for Flutter client
- [ ] Achieve 80%+ code coverage for Go services
- [ ] Implement test doubles for external dependencies
- [ ] Create property-based tests for critical logic
- [ ] VERIFY: Run coverage reports and confirm targets met
- [ ] VERIFY: Review uncovered code and add tests where critical
- [ ] SECURITY CHECKPOINT: Confirm tests do not contain real credentials

### 13.2 Integration Testing
- [ ] Create integration tests for API endpoints
- [ ] Implement database integration tests with test containers
- [ ] Create WebSocket integration tests
- [ ] Implement sync integration tests with network simulation
- [ ] VERIFY: Run integration tests in CI/CD pipeline
- [ ] VERIFY: Test failure scenarios and confirm graceful degradation
- [ ] SECURITY CHECKPOINT: Confirm integration tests use test data only

### 13.3 End-to-End Testing
- [ ] Implement E2E tests using integration_test (Flutter)
- [ ] Create critical user journey tests (registration, messaging, posting)
- [ ] Implement E2E tests for offline scenarios
- [ ] Create visual regression tests for UI components
- [ ] VERIFY: Run E2E tests on multiple device form factors
- [ ] VERIFY: Test critical journeys with network interruption
- [ ] SECURITY CHECKPOINT: Confirm E2E tests do not expose real user data

### 13.4 Security Testing
- [ ] Implement automated security scanning in CI/CD
- [ ] Create security regression tests for known vulnerabilities
- [ ] Implement secret scanning tests
- [ ] Create penetration test scenarios
- [ ] VERIFY: Run security scanners and confirm zero critical issues
- [ ] VERIFY: Test secret scanning with fake secrets
- [ ] SECURITY CHECKPOINT: Confirm security tests are comprehensive

### 13.5 Performance Testing
- [ ] Implement load testing for API endpoints
- [ ] Create performance benchmarks for critical operations
- [ ] Implement memory leak detection tests
- [ ] Create battery usage tests for mobile client
- [ ] VERIFY: Run load tests and confirm SLA compliance
- [ ] VERIFY: Profile memory usage over extended sessions
- [ ] SECURITY CHECKPOINT: Confirm performance tests do not compromise security

---

## Phase 14: Deployment & Monitoring

### Objective
Implement production deployment pipeline, monitoring, and incident response procedures.

### 14.1 Production Deployment Pipeline
- [ ] Create blue-green deployment strategy
- [ ] Implement canary releases for new features
- [ ] Create database migration scripts for production
- [ ] Implement feature flag system
- [ ] VERIFY: Test deployment pipeline in staging environment
- [ ] VERIFY: Test rollback procedure
- [ ] SECURITY CHECKPOINT: Confirm deployment pipeline does not expose secrets

### 14.2 Monitoring & Alerting
- [ ] Configure Grafana dashboards for all services
- [ ] Implement alerting rules for critical metrics
- [ ] Create incident response runbooks
- [ ] Implement on-call rotation system
- [ ] VERIFY: Test alerting by simulating failures
- [ ] VERIFY: Review dashboards with operations team
- [ ] SECURITY CHECKPOINT: Confirm monitoring data does not contain PII

### 14.3 Log Management & Analysis
- [ ] Configure Loki log retention policies
- [ ] Implement log aggregation for all services
- [ ] Create log analysis queries for troubleshooting
- [ ] Implement log-based alerting
- [ ] VERIFY: Test log aggregation and confirm all services are captured
- [ ] VERIFY: Verify PII scrubbing in logs
- [ ] SECURITY CHECKPOINT: Confirm logs are scrubbed of PII before storage

### 14.4 Backup & Disaster Recovery
- [ ] Implement automated database backups (daily)
- [ ] Create backup verification scripts
- [ ] Implement disaster recovery procedures
- [ ] Create backup restoration tests
- [ ] VERIFY: Test backup restoration in staging environment
- [ ] VERIFY: Measure RTO and RPO targets
- [ ] SECURITY CHECKPOINT: Confirm backups are encrypted at rest

### 14.5 Incident Response
- [ ] Create incident response playbook
- [ ] Implement incident severity classification
- [ ] Create communication templates for incidents
- [ ] Implement post-incident review process
- [ ] VERIFY: Conduct incident response drill
- [ ] VERIFY: Review and update playbook based on drill
- [ ] SECURITY CHECKPOINT: Confirm incident response does not expose sensitive data

---

## Phase 15: Documentation & Handover

### Objective
Create comprehensive documentation for developers, operators, and users to ensure long-term maintainability.

### 15.1 Developer Documentation
- [ ] Create API documentation (OpenAPI/Swagger)
- [ ] Write architecture decision records (ADRs)
- [ ] Create contributor guidelines
- [ ] Implement code documentation standards (JSDoc, GoDoc)
- [ ] VERIFY: Review API documentation with development team
- [ ] VERIFY: Test code examples in documentation
- [ ] SECURITY CHECKPOINT: Confirm documentation does not expose secrets

### 15.2 Operations Documentation
- [ ] Create deployment guides
- [ ] Write runbooks for common operations
- [ ] Create troubleshooting guides
- [ ] Implement infrastructure documentation
- [ ] VERIFY: Test deployment guides in staging environment
- [ ] VERIFY: Review runbooks with operations team
- [ ] SECURITY CHECKPOINT: Confirm operations docs do not expose credentials

### 15.3 User Documentation
- [ ] Create user onboarding guides
- [ ] Write FAQ documentation
- [ ] Create video tutorials for key features
- [ ] Implement in-app help system
- [ ] VERIFY: Test user guides with beta users
- [ ] VERIFY: Review tutorials for clarity
- [ ] SECURITY CHECKPOINT: Confirm user docs do not expose technical details

### 15.4 Security Documentation
- [ ] Create security whitepaper
- [ ] Write penetration test reports
- [ ] Implement security FAQ for users
- [ ] Create bug bounty program documentation
- [ ] VERIFY: Review security whitepaper with security team
- [ ] VERIFY: Publish bug bounty program
- [ ] SECURITY CHECKPOINT: Confirm security docs are accurate and comprehensive

---

## Appendix: Security Checkpoints Summary

### Critical Security Rules to Verify
1. **Zero-Plaintext Logging:** No `print()` or `debugPrint()` outputs raw payload data
2. **No Server-Side Decryption:** Vault and War Room content never decrypts on server
3. **No Device Fingerprinting:** Root/jailbreak detection is local-only, no telemetry
4. **FLAG_SECURE Enforcement:** Vault and War Room screens block screenshots
5. **No Cloud AI for PII:** PII redaction uses local models or deterministic logic only
6. **Zero-Retention Translation:** Cross-lingual translation drops plaintext immediately
7. **No Phone Number Persistence:** Raw phone numbers are hashed and discarded
8. **Offline-First Enforcement:** All network requests go through local queue first
9. **No Direct HTTP from UI:** UI components bind to local state, not network futures
10. **Strict Package Management:** No dependencies added without explicit permission

### Verification Commands
```bash
# Secret scanning
gitleaks detect --source .

# Security scanning
trivy image <image-name>
gosec ./...

# Dependency scanning
dependabot status
npm audit (if applicable)

# Log scrubbing verification
# Inject fake PII into logs and confirm scrubbing
```

---

## Progress Tracking

**Current Phase:** Phase 6 - The Vault (Secure Messaging)  
**Current Task:** 6.6 Duress PIN Integration COMPLETE — next: Phase 7 Task 7.1 Ledger UI Foundation  
**Overall Progress:** Phase 2 complete (2.1–2.7); Phase 3 COMPLETE (3.1–3.6); Phase 4 COMPLETE (4.1–4.8); Phase 5 COMPLETE (5.1–5.6); Phase 6 COMPLETE (6.1–6.6)

**Last Updated:** 2026-08-10  
**Next Review:** After completion of Task 7.1

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2026-07-04 | 1.0 | Initial MASTER_PLAN creation |
| 2026-07-04 | 1.1 | Completed Phase 1.1 - Repository & Development Environment Setup |
| 2026-08-02 | 1.2 | Completed Task 4.2 - API Gateway (Kong OSS), live-verified (JWT 401/200, per-blind_hash_id throttle, IP stripping, PII-scrubbed logs) |
| 2026-08-03 | 1.3 | Completed Task 4.3 - Identity Service (Go) — OTP/MSG91, Argon2id blind-hash w/ Vault salt, username cooldown, device keys, stdlib RS256 JWT + rotating refresh, Redis OTP/revocation; 73 unit tests + live smoke test; phone-never-persisted checkpoint passed |
| 2026-08-04 | 1.4 | Completed Task 4.4 - Messaging Relay Service (Go) — WebSocket connections (coder/websocket, first-frame JWT auth, 25s/10s heartbeat), ciphertext envelope routing with server-verified sender hashes, Redis Streams offline queue (30-day TTL, purge on ack), multi-device fan-out, connection-request state machine; 114 Go tests (41 new relay) + live smoke test (12/12); never-decrypts checkpoint passed |
| 2026-08-04 | 1.5 | Completed Task 4.5 - PostgreSQL Schema & Migrations — embedded migration runner (forward/rollback, advisory-locked) creating users/usernames/devices/refresh_tokens/connection_requests with postgis/pgcrypto/pg_stat_statements/uuid-ossp; ENABLE+FORCE RLS with civic_app-scoped policies (live out-of-scope denial verified); pgcrypto encryption at rest for device keys; PostgreSQL-backed stores wired into identity + relay; primary/standby replication + WAL-archive-to-MinIO declarative configs; 133 Go tests (18 new) + live Postgres verification; pgcrypto/RLS security checkpoint passed |
| 2026-08-04 | 1.6 | Completed Task 4.6 - Redis Configuration — production Redis client factory (go-redis/v9) with Sentinel HA failover, resilient retries (3, backoff 8ms→512ms), managed pooling (size 20, min-idle 5) and a Ping health probe wired into identity + relay (fail-fast in production); validated namespace registry (otp/otp_attempts/refresh/revoked/revoked_family/msg_queue + karma/vote_buffer/analyst_load/rate) with spec TTL policies and PII-rejecting key builders adopted by all Redis stores; Redis Sentinel Helm chart (1 primary, 2 replicas, 3 sentinels, AOF+RDB persistence, PVC, sh-based probes); 152 Go tests (19 new) + live 6-container Sentinel verification incl. kill-the-primary failover demo; no-plaintext-PII checkpoint passed |
| 2026-08-04 | 1.7 | Completed Task 4.7 - NATS JetStream Event Bus — JetStream client (stream init, PUBACK publish, explicit durable consumers via create+bind, auto-reconnect handlers), validated allowlist topic schema (relay.connection.accepted, identity.user.registered, karma.updated, search.sync.requested), at-least-once delivery; NATS Helm chart (JetStream file storage on PVC); 170 Go tests (18 new incl. embedded-nats-server restart-resume/no-loss + concurrent durable race + option fallback) + live docker verification (8/8 incl. broker-restart durability); zero-PII checkpoint passed |
| 2026-08-04 | 1.8 | Completed Task 4.8 - HashiCorp Vault Integration — expanded stdlib net/http Vault client (no SDK): AppRole login + background token renewal (LookupSelf/RenewSelf + re-login loop), KV v2 reads + metadata, Transit encrypt/decrypt helpers, TTL-aware SecretCache with rotation-detecting refresh + buffer wipe, WipeBytes hygiene, fail-fast Connect factory wired into identity + relay; redacting logger scrubs Vault tokens (hvs./s.), X-Vault-Token and Authorization headers; production config refuses to run without Vault auth; 190 Go tests (20 new) + live docker Vault verification (AppRole/KV/transit/cache/wrong-token/redaction) + deps checkpoint; secrets-never-logged checkpoint passed |
| 2026-08-04 | 1.9 | Completed Task 5.1 - Network State Detection (debounced 500ms listener via new DebouncedNetworkInfoProvider; mapping + scripted-transition + fakeAsync debounce tests) and Task 5.2 - Sync Worker / Offline Mutation Queue (UUID v4 idempotency keys wired into every queue mutation, 10s aggressive per-push timeout, crash recovery recoverInterrupted(), backoff jitter, deterministic LWW conflict hooks); 412 Flutter tests (33 new); Phase 4 + 5.1/5.2 fully verified (go test -race green, golangci-lint 0, deps + live Vault checks passed) |
| 2026-08-05 | 1.10 | Completed Task 5.3 - Idempotency Enforcement (server-side Redis dedup) — new `internal/idempotency` package (SETNX claim / get / complete / clear middleware wrapped around the relay's POST mutation routes inside auth): missing header = passthrough, malformed UUID = 400, in-flight = 409, completed = cached replay with `Idempotent-Replayed` header, handler failure = key cleared; actor-scoped keys `idempotency:{blind_hash_id}:{uuid}` under the validated `idempotency:` cache namespace (24h TTL, `IDEMPOTENCY_TTL` configurable) so cross-user replay is impossible and no PII can enter keys; 211 Go test funcs (18 new idempotency + 5 relay HTTP integration + namespace/config) — full `go test -race` green (11 suites), golangci-lint 0 violations, gofmt/vet clean, deps checkpoint passed |
| 2026-08-05 | 1.11 | Completed Task 5.4 - Sync Status UI Integration — new `SyncStatusBar` (`lib/state/ui/`) renders LIVE/CACHED/QUEUED/OFFLINE with per-state color+icon, pending-count badge, a 14px progress indicator while a sync run is in flight, and tap-to-expand showing "Last synced" + queue count; state contract extended additively with non-PII `lastSyncAt` + `isSyncing` (bloc stamps lastSyncAt exactly when the queue drains while online via injectable clock; isSyncing derives from in-progress queue items); widget consumes ONLY the `SyncStatusBloc` stream — no data-layer access; 447 Flutter tests total (34 new: 22 widget + 2 end-to-end integration via real ReconnectionSyncTrigger/BackgroundSyncWorker + 5 UI security scans + 5 bloc derivation), `flutter analyze` 0 errors, full suite green (also removed stale `flutter create` scaffold test that referenced a nonexistent main.dart) |
| 2026-08-09 | 1.13 | Completed Task 5.6 - Offline Queue Persistence (final task of Phase 5) — durable SQLCipher queue with exact serialization/deserialization bounds, `recoverInterrupted()` cold-start recovery, `purgeExpired` 30-day retention (strict boundary, wired into the worker before every drain), max-1000 FIFO eviction (in-flight protected, just-inserted item guaranteed to survive by construction), sealed-only versioned backup/restore envelope (`SyncQueueBackup`, idempotent restore, fully validated before any insert); 522 Flutter tests (35 new: 15 queue-repo incl. 4 purge + 5 serialization bounds + FIFO/tie, 10 backup codec, 2 cold-restart integration, 4 worker expiry cleanup, 3 ciphertext-at-rest checkpoint, security scans), `flutter analyze` 0 errors, suite green; queue-encrypted-at-rest checkpoint passed; **PHASE 5 COMPLETE** — next: Phase 6 Task 6.1 Vault UI Foundation |
| 2026-08-09 | 1.14 | Completed Task 6.1 - Vault UI Foundation (first task of Phase 6) — `VaultMasthead` (classified-document strip: Vault Blue #1A3D6B, `THE VAULT` wordmark, `[CLASSIFIED]` stamp, black pseudo-redaction bar), `VaultConversationListScreen` (BLoC-stream list with fixed `[end-to-end encrypted]` ciphertext previews + collapsible `VaultPendingRequestsSection` request queue + FAB), `VaultConversationDetailScreen` + `MessageBubble` (received white w/ 3dp Vault Blue left bar, sent Vault Blue; ✓/✓✓ receipts, amber queued indicator, Expires marker, fixed E2EE placeholder body) + static composer placeholder; new non-PII `formatPeerHandle` (derived `@peer_` + 6-hex display handles — never the raw blind hash); both screens wrap in `SecureScreenWrapper` (FLAG_SECURE) with late-subscribe `refresh()` on mount; 572 Flutter tests (50 new: 6 peer-handle + 8 masthead + 10 list + 2 real-BLoC integration + 13 detail/bubbles + 11 security scans incl. FLAG_SECURE-on-mount + runtime PII scans), `flutter analyze` 0 errors, suite green; FLAG_SECURE-on-all-Vault-screens + zero-PII-in-Vault-UI checkpoints passed |
| 2026-08-09 | 1.15 | Completed Task 6.2 - Connection Request Flow — backend username search via API Gateway: new auth-required `GET /v1/identity/username/{username}` (`LookupUsername`, policy-validated, 404 for unknown/released usernames, `{username, blind_hash_id}` response only; 5 Go tests incl. no-phone-in-response/logs); relay `ConnectionRequest` JSON-tag fix (snake_case wire contract); client connection-request domain/data/state layers — `ConnectionRequest` entity + single-transition CAS repository (blind-hash-only targets, sealed sync envelopes, idempotent-while-pending), `connection_requests` row codecs, `ConnectionRequestsBloc` inbox projection + `UserSearchBloc`; Task 6.1 queue is now BLoC-driven with wired Accept, new FLAG_SECURE `UsernameSearchSheet`, conversation tiles resolve remembered public usernames; stale-snapshot guard + directory-failure resilience; 612 Flutter tests (40 new), `flutter analyze` 0 errors, suite green; 216 Go test funcs, `go test -race` green, golangci-lint 0 violations; zero-phone-in-connection-requests checkpoint passed; key exchange on approval deferred to Task 6.3 |
| 2026-08-10 | 1.17 | Completed Task 6.4 - WebSocket Message Relay — new `lib/relay/` tree (domain: `RelayEnvelope`/sealed `RelayFrame` codec mirroring the Go relay's protojson `UseProtoNames` wire exactly (oneof members auth/auth_ack/envelope/ack/error, snake_case, base64 ciphertext, `DiscardUnknown`), `RelaySocket`/`RelaySocketConnector` ports, `RelayHeartbeat` data-frame watchdog, `RelayClient` orchestration (first-frame JWT auth in body, read loop, envelope auto-ack, reconnect with the Task 5.2 jittered backoff, dummy-traffic keepalive opt-in), `DummyTrafficGenerator`; data: `WebSocketRelaySocket` over `web_socket_channel` ^2.4.0 with transport-level `pingInterval: 20s` (dart:io closes on missed pong — the correct dead-connection detector since the relay's 25s pings are protocol control frames invisible to data-frame watchdogs; app watchdog gated by `hasTransportHeartbeat`); production hardening from code review: a drop during the auth handshake before any auth_ack is TRANSIENT (reconnects with backoff) while an explicit `auth_ack:false` is terminal and its policy-violation close is never retried (`_authRejected` flag, generation-guarded); 691 Flutter tests total (36 new: wire codec round-trips incl. the EXACT Go protojson shape, fake_async heartbeat watchdog, RelayClient lifecycle incl. pre-auth-drop reconnect + rejection-close terminal + transport-heartbeat-skips-watchdog + stale watchdog, real dart:io WebSocket integration lifecycle, security checkpoint: JWT in body not URL / no PII literals / no print / ciphertext never logged), `flutter analyze` 0 issues, suite green (2 Argon2id-heavy files hang only at the tail of the long serial run — pass in isolation); zero-PII + JWT-in-body-not-URL + ciphertext-never-logged checkpoints passed; next: Task 6.5 Multi-Device Pairing |
| 2026-08-10 | 1.19 | Completed Task 6.6 - Duress PIN Integration — new `VaultUnlockBloc`/`VaultUnlockState`/`DuressSetupBloc`/`DuressSetupState` (state/domain) + `LocalVaultUnlockBloc`/`LocalDuressSetupBloc` (state/data) wrapping the Phase 2.5 `DuressService`; **one PIN prompt for both PINs**: `VaultUnlockScreen` (FLAG_SECURE, obscured numeric PIN, spinner, SINGLE generic error) calls `unlock(pin)` which returns the opened `UnlockResult` (real vs decoy vault) ONLY to the routing callback — the state stream never reveals which vault was opened, and near-real vs near-duress failures are byte-identical; **decoy vault**: `DecoyVaultScreen` renders the SAME `VaultMasthead` + CONVERSATIONS header + the shared `VaultEmptyState` (extracted from the real list) — takes NO data inputs, references no bloc/repository/entity types, FLAG_SECURE wrapped (indistinguishable by security guard too), proven byte-identical to the real empty list by a rendered-text comparison test; **database switching**: real PIN opens `vault.db` / duress PIN opens `vault_decoy.db` purely by decryption — real records persist in the real vault and are INVISIBLE through the decoy result (integration-verified); **onboarding setup**: `DuressPinSetupSheet` (the ONE screen that labels the two obscured PIN fields), identical/empty/duplicate registrations all map to one generic error, PINs wiped from controllers after every attempt; 824 Flutter tests total (46 new: 9 unlock-bloc incl. DB switching + record isolation + generic failure matrix + failing-service degradation, 5 setup-bloc, 13 unlock-screen widget incl. real/decoy routing + byte-identical failure UI + FLAG_SECURE + PII scan, 4 decoy-screen widget incl. text-identity-vs-real-empty + FLAG_SECURE, 5 setup-sheet widget, 5 real-service integration incl. persisted-file indicator scan, 5 security checkpoint), `flutter analyze` 0 issues, affected suites 105/105 green (the pre-existing Argon2id `duress_service_test` batch-hang artifact unchanged — passes 16/16 in isolation); SECURITY CHECKPOINT PASSED: duress PIN indistinguishable from real PIN — static scans (unlock screen never references real/duress/decoy/VaultKind in code, never inspects result kind, state models carry no key/DB fields, no print/PII literals) + runtime (identical failure UI, decoy text ≡ real-empty text) + persisted vault bytes contain no real/duress/decoy indicator; next: Phase 7 Task 7.1 Ledger UI Foundation |
| 2026-08-10 | 1.18 | Completed Task 6.5 - Multi-Device Pairing — new `lib/pairing/` tree (domain: `PairingPayload` strict zero-PII QR codec (civic-commons://pair URI, 64-hex blind hash + UUID v4 + one-time 32-byte secret + PUBLIC keys only, base64url-unpadded wire, `DiscardUnknown`-tolerant decode, hard rejection of any PII-shaped field), `PairingSecretGenerator` (32-byte CSPRNG, 5-min window), `QrMatrix` value object + `QrEncoder`/`QrScanner` ports, `LinkedDevice` entity + `DeviceRegistry` port, `DevicePairingService` orchestrator, `IdentityKeySource` port); data: `qr_codec_impl.dart` wrapping the pure-Dart `qr` package (medium ECC, byte→module only — never interprets payload), `local_device_registry.dart` (EntityStore-backed, blind-hash-keyed), `secure_storage_identity_key_source.dart` (Keystore-backed); **code-review hardening (critical)**: the QR signed-prekey signature is now a REAL Ed25519 signature computed in `createPairingPayload` (the PrekeyManager/block placeholders are never trusted) and `authorizePayloadText` CRYPTOGRAPHICALLY verifies it against the embedded identity key BEFORE any session/registration — tampered/substituted spk/ik rejected (photographed-QR MITM protection); the one-time pairing secret is single-use (consumed on first successful authorize — replay rejected); schema migration v4 adds the `devices` table (SQLCipher row codecs, forward+rollback tested); state layer: `LinkedDevicesBloc` + `DevicePairingBloc` (sync broadcast per codebase convention) + `formatDeviceHandle` (derived `DEV_` + 6-hex, never raw UUIDs/keys); FLAG_SECURE UI: `DeviceManagementSheet` (list + revoke + QR panel), `PairingQrView` (CustomPaint matrix — payload text never rendered), `PairingScanSheet` (manual code entry, camera `QrScanner` port documented); 778 Flutter tests total (84 new: 73 pairing incl. 5 security — real-signature-verifies, tampered-spk/tampered-ik rejection, single-use replay, private-key-never-in-payload, plus 4 direct `SecureStorageIdentityKeySource` tests, 11 widget tests, schema/migration v4 updates), `flutter analyze` 0 issues, suite green (known Argon2id batch-hang artifact unchanged); SECURITY CHECKPOINT PASSED: QR-local key transfer (no cloud backup/sync/upload identifiers in code, word-boundary scans), zero PII in payload/UI/logs, FLAG_SECURE on all pairing screens, private keys never leave secure storage; next: Task 6.6 Duress PIN Integration |
| 2026-08-10 | 1.16 | Completed Task 6.3 - Message Encryption & Decryption — X3DH session establishment wired into the connection-approval hook (deferred from 6.2): `SessionManager` (initiator/responder X3DH via `X3DHService` + per-peer Double Ratchet stored in `SessionStore` keyed by 64-hex blind hash), `PreKeyBundleSource` port + in-memory registry, `SessionEstablisher` port (`LocalSessionEstablisher`) invoked best-effort by `LocalConnectionRequestsBloc.accept` — a missing bundle never fails the local accept; composer wiring: real `ConversationComposer` replaces the static 52dp placeholder, `MessageBloc.send` encrypts via the `MessageCipher` port (`SignalMessageCipher`) and persists offline-first as `direction: sent, delivered: false` (queued sealed payload); message decryption: `MessageSummary.content` now carries DECRYPTED plaintext (BLoC decrypt-on-emit with stale-snapshot guard) and `MessageBubble` renders it, falling back to the fixed `[end-to-end encrypted]` placeholder when undecryptable — never raw ciphertext; explicit `MessageDirection` field on the `Message` entity + schema migration v3 (`messages.direction`, backfilled by the old delivered-heuristic so existing sent/received rows keep their side) supersedes the heuristic `MessageSideResolver`; 655 Flutter tests (43 new: 9 session manager + 7 establisher/cipher + 9 message-bloc encrypt/decrypt + 3 bubble content + 5 composer + 3 approval-hook + direction/schema/migration/copyWith), `flutter analyze` 0 issues, suite green; 216 Go test funcs, `go test -race` green, golangci-lint 0 violations; zero-plaintext-logged + no-ciphertext-in-state + FLAG_SECURE-intact checkpoints passed; read-receipt ✓✓✓ and TTL deletion deferred to later Phase 6 tasks |

