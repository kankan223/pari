# Civic Commons — Master Implementation Plan

**Version:** 1.0  
**Status:** Active  
**Last Updated:** 2026-07-04  
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
- [ ] Implement Argon2id hashing for phone numbers with salt fetched from secure backend
- [ ] Create phone number validation (E164 format)
- [ ] Implement salt rotation logic (quarterly) with fallback support
- [ ] Create blind hash ID generation and storage
- [ ] VERIFY: Write unit tests for phone hashing with known salt and confirm output matches expected hash
- [ ] VERIFY: Write unit tests for salt rotation and confirm old hashes can still be validated
- [ ] SECURITY CHECKPOINT: Confirm raw phone numbers are never persisted to disk or logged

### 2.5 Duress PIN Implementation
- [ ] Implement dual PIN registration flow (real PIN + duress PIN)
- [ ] Create separate database key derivation paths for each PIN
- [ ] Implement decoy database (`vault_decoy.db`) initialization
- [ ] Create database selection logic based on which PIN successfully decrypts
- [ ] VERIFY: Write unit tests for duress PIN unlocking decoy database
- [ ] VERIFY: Write unit tests for real PIN unlocking real database
- [ ] SECURITY CHECKPOINT: Confirm app never stores which PIN is real vs duress

### 2.6 Hardware Security Integration
- [ ] Implement `FLAG_SECURE` wrapper for Android using platform channel
- [ ] Create secure screen wrapper widget for Vault and War Room screens
- [ ] Implement root/jailbreak detection (local only, no telemetry)
- [ ] Create graceful degradation flow for rooted devices (warning, not block)
- [ ] VERIFY: Test on Android device and confirm screenshot is blocked when FLAG_SECURE is active
- [ ] VERIFY: Test on rooted device and confirm warning appears without sending telemetry
- [ ] SECURITY CHECKPOINT: Confirm no device fingerprinting data is sent to server

### 2.7 Zero-Plaintext Logging System
- [ ] Create custom logging wrapper that redacts PII patterns
- [ ] Implement hash-only logging for sensitive operations (log hash IDs, not raw data)
- [ ] Add boolean success/fail logging for cryptographic operations
- [ ] Configure logging levels for development vs production
- [ ] VERIFY: Write unit tests that attempt to log PII and confirm redaction occurs
- [ ] VERIFY: Write unit tests for hash-only logging and confirm reversibility is impossible
- [ ] SECURITY CHECKPOINT: Confirm no `print()` or `debugPrint()` outputs raw payload data

---

## Phase 3: Offline-First SQLite/Queue Repository

### Objective
Build the local data layer with SQLCipher encryption and a queue-based sync system that ensures the app works offline and syncs resiliently when connectivity returns.

### 3.1 SQLCipher Database Schema Design
- [ ] Define Drift/SQLCipher schema for core entities:
  - `users` (blind_hash_id, username, device_pubkey)
  - `conversations` (id, participant_hash, encrypted_session_state)
  - `messages` (id, conversation_id, ciphertext, delivered, expires_at)
  - `connection_requests` (id, requester_hash, recipient_hash, status)
  - `sync_queue` (id, operation_type, payload, status, retry_count)
- [ ] Create database migration system
- [ ] Implement database key derivation from user PIN (Argon2id)
- [ ] VERIFY: Write unit tests for schema creation and migration
- [ ] VERIFY: Write unit tests for database encryption/decryption with wrong key failure
- [ ] SECURITY CHECKPOINT: Confirm all sensitive columns are encrypted at rest

### 3.2 Repository Pattern Implementation
- [ ] Create abstract `BaseRepository` class with standard CRUD operations
- [ ] Implement `ConversationRepository` for Vault data
- [ ] Implement `MessageRepository` with local-first read/write
- [ ] Implement `SyncQueueRepository` for pending operations
- [ ] Create repository interface that returns local data immediately, then syncs
- [ ] VERIFY: Write unit tests for repository CRUD operations
- [ ] VERIFY: Write unit tests for repository returning cached data before sync
- [ ] SECURITY CHECKPOINT: Confirm repositories never make direct HTTP calls

### 3.3 Sync Queue Implementation
- [ ] Create `SyncQueueItem` model with fields: operation_type, payload, status, retry_count, created_at
- [ ] Implement queue status enum: `pending`, `in_progress`, `success`, `failed`
- [ ] Create queue insertion logic for all mutation operations (POST, PUT, DELETE)
- [ ] Implement retry logic with exponential backoff (1s, 2s, 4s ... 5 min max)
- [ ] VERIFY: Write unit tests for queue insertion and status transitions
- [ ] VERIFY: Write unit tests for exponential backoff calculation
- [ ] SECURITY CHECKPOINT: Confirm queued payloads are encrypted before storage

### 3.4 WorkManager Background Sync
- [ ] Configure `workmanager` plugin for background task execution
- [ ] Create background sync worker that processes pending queue items
- [ ] Implement network state detection using `connectivity_plus`
- [ ] Create sync trigger on network reconnection
- [ ] Implement chunking logic for batch operations (max 10 items per batch)
- [ ] VERIFY: Write integration tests for background sync execution
- [ ] VERIFY: Write unit tests for network state detection
- [ ] SECURITY CHECKPOINT: Confirm background sync respects offline-first architecture

### 3.5 Local State Management (BLoC/Cubit)
- [ ] Create BLoC for conversation state (streams from local database)
- [ ] Create BLoC for message state (streams from local database)
- [ ] Create BLoC for sync status (LIVE, CACHED, QUEUED, OFFLINE)
- [ ] Implement state persistence using Hive for non-sensitive data
- [ ] VERIFY: Write unit tests for BLoC state transitions
- [ ] VERIFY: Write unit tests for database stream emissions to BLoC
- [ ] SECURITY CHECKPOINT: Confirm BLoC never exposes raw decrypted data in logs

### 3.6 Hive Local Storage for Non-Sensitive Data
- [ ] Create Hive boxes for: ledger_drafts, academy_progress, karma_cache
- [ ] Implement Hive initialization with encryption for sensitive boxes
- [ ] Create cache invalidation logic for karma scores (5 min TTL)
- [ ] VERIFY: Write unit tests for Hive CRUD operations
- [ ] VERIFY: Write unit tests for cache invalidation TTL logic
- [ ] SECURITY CHECKPOINT: Confirm no PII or sensitive data in unencrypted Hive boxes

---

## Phase 4: API Gateway & Backend Services Foundation

### Objective
Build the API Gateway layer and core backend services in Go, implementing the service boundary architecture defined in the technical stack.

### 4.1 Go Project Structure & Dependencies
- [ ] Create Go 1.22+ project with standard layout: `/cmd`, `/internal`, `/pkg`
- [ ] Initialize Go modules with pinned versions from TECHSTACK.md
- [ ] Add dependencies: `go-sqlcipher`, `lib/pq`, `go-redis`, `nats.go`, `minio-go`
- [ ] Configure `golangci-lint` with custom rules
- [ ] Set up `go generate` for protocol buffer compilation
- [ ] VERIFY: Run `go mod tidy` and confirm no dependency conflicts
- [ ] VERIFY: Run `golangci-lint run` and confirm no violations
- [ ] SECURITY CHECKPOINT: Confirm no cloud-based AI or telemetry SDKs in Go dependencies

### 4.2 API Gateway (Kong OSS)
- [ ] Deploy Kong OSS 3.x via Helm chart
- [ ] Configure JWT plugin with RS256 validation
- [ ] Configure rate-limiting-advanced plugin per blind_hash_id
- [ ] Configure request-transformer to strip X-Forwarded-For
- [ ] Configure response-transformer to remove server headers
- [ ] Configure bot-detection plugin
- [ ] Configure correlation-id injection
- [ ] Configure PII scrubbing for access logs
- [ ] VERIFY: Test JWT validation with invalid token and confirm 401 response
- [ ] VERIFY: Test rate limiting with rapid requests and confirm throttling
- [ ] SECURITY CHECKPOINT: Confirm IP addresses are stripped before upstream requests

### 4.3 Identity Service (Go)
- [ ] Implement OTP verification endpoint (Twilio Verify or MSG91 integration)
- [ ] Implement Argon2id phone-to-blind-hash with salt from HashiCorp Vault
- [ ] Implement username claim/release with cooldown (30 days)
- [ ] Implement device public-key registration
- [ ] Implement JWT issuance (RS256, 15-minute access tokens)
- [ ] Implement refresh token management with rotation
- [ ] Configure Redis for OTP codes (TTL 10 min) and refresh token revocation
- [ ] VERIFY: Write unit tests for OTP verification flow
- [ ] VERIFY: Write unit tests for JWT issuance and validation
- [ ] SECURITY CHECKPOINT: Confirm raw phone numbers are never persisted or logged

### 4.4 Messaging Relay Service (Go)
- [ ] Implement WebSocket connection management
- [ ] Implement ciphertext envelope routing (sender hash → recipient hash)
- [ ] Implement offline queue using Redis Streams (TTL 30 days)
- [ ] Implement multi-device fan-out logic
- [ ] Implement delivery acknowledgement and queue purge
- [ ] Implement Connection Request state machine
- [ ] VERIFY: Write unit tests for WebSocket message routing
- [ ] VERIFY: Write unit tests for offline queue TTL expiration
- [ ] SECURITY CHECKPOINT: Confirm service never attempts to decrypt message bodies

### 4.5 PostgreSQL Schema & Migrations
- [ ] Create PostgreSQL 16 database with extensions: postgis, pgcrypto, pg_stat_statements, uuid-ossp
- [ ] Define schema tables: users, usernames, devices, refresh_tokens, connection_requests
- [ ] Configure row-level security (RLS) for sensitive tables
- [ ] Set up streaming replication to two standbys
- [ ] Configure WAL archiving to MinIO for PITR
- [ ] VERIFY: Write unit tests for schema migrations
- [ ] VERIFY: Test RLS by attempting to query rows outside permission scope
- [ ] SECURITY CHECKPOINT: Confirm PII columns use pgcrypto encryption at rest

### 4.6 Redis Configuration
- [ ] Deploy Redis Sentinel (3-node: 1 primary, 2 replicas, 3 sentinels)
- [ ] Configure key namespaces: otp, refresh, revoked, msg_queue, karma, vote_buffer, analyst_load, rate
- [ ] Set up TTL policies for each namespace
- [ ] Configure Redis persistence (AOF + RDB)
- [ ] VERIFY: Write integration tests for Redis operations
- [ ] VERIFY: Test TTL expiration by setting keys and confirming deletion
- [ ] SECURITY CHECKPOINT: Confirm no plaintext PII in Redis values

### 4.7 NATS JetStream Event Bus
- [ ] Deploy NATS JetStream with durable streams
- [ ] Define topic schema for karma events and search sync
- [ ] Configure at-least-once delivery guarantees
- [ ] Implement consumer groups for karma service
- [ ] VERIFY: Write integration tests for event publishing and consumption
- [ ] VERIFY: Test durability by restarting NATS and confirming no event loss
- [ ] SECURITY CHECKPOINT: Confirm event payloads contain no plaintext PII

### 4.8 HashiCorp Vault Integration
- [ ] Deploy HashiCorp Vault via Helm chart
- [ ] Configure transit secrets engine for encryption operations
- [ ] Configure KV secrets engine for Argon2id salt and JWT signing keys
- [ ] Implement Go client for Vault secrets fetching
- [ ] Set up automatic secret rotation policies
- [ ] VERIFY: Write unit tests for Vault client operations
- [ ] VERIFY: Test secret rotation and confirm service picks up new values
- [ ] SECURITY CHECKPOINT: Confirm secrets are never written to application logs

---

## Phase 5: State Management & Sync Engine

### Objective
Implement the resilient background sync engine that bridges the local SQLite queue with the remote API Gateway, handling network volatility and ensuring data consistency.

### 5.1 Network State Detection
- [ ] Implement `NetworkInfoProvider` using `connectivity_plus`
- [ ] Create network state enum: `online`, `offline`, `metered`
- [ ] Implement network state listener with debouncing (500ms)
- [ ] Create network-aware sync triggering logic
- [ ] VERIFY: Write unit tests for network state detection
- [ ] VERIFY: Write integration tests by toggling network and confirming state changes
- [ ] SECURITY CHECKPOINT: Confirm network state is not used for fingerprinting

### 5.2 Sync Worker Implementation
- [ ] Create background isolate for sync operations using `workmanager`
- [ ] Implement chunking logic: process queue items in batches of 10
- [ ] Implement aggressive timeout limits: 10s per HTTP request
- [ ] Implement idempotency key generation and attachment to headers
- [ ] Implement silent failure handling: increment retry count, update timestamp, no UI exception
- [ ] VERIFY: Write unit tests for chunking logic
- [ ] VERIFY: Write unit tests for idempotency key generation
- [ ] SECURITY CHECKPOINT: Confirm sync worker never exposes plaintext payloads in logs

### 5.3 Idempotency Enforcement
- [ ] Implement UUID v4 idempotency key generation
- [ ] Attach `Idempotency-Key` header to all mutation requests
- [ ] Implement server-side idempotency key tracking in Redis (TTL 24 hours)
- [ ] Create idempotency conflict resolution logic
- [ ] VERIFY: Write unit tests for idempotency key generation
- [ ] VERIFY: Write integration tests by sending duplicate requests and confirming deduplication
- [ ] SECURITY CHECKPOINT: Confirm idempotency keys are random and not predictable

### 5.4 Sync Status UI Integration
- [ ] Create `SyncStatusBar` widget showing: LIVE, CACHED, QUEUED, OFFLINE
- [ ] Implement tap-to-expand showing last-sync timestamp and queue count
- [ ] Bind sync status to BLoC state stream
- [ ] Implement visual feedback for sync operations (subtle progress indicator)
- [ ] VERIFY: Write widget tests for SyncStatusBar states
- [ ] VERIFY: Write integration tests by triggering sync and confirming UI updates
- [ ] SECURITY CHECKPOINT: Confirm sync status never exposes sensitive data

### 5.5 Conflict Resolution Logic
- [ ] Implement last-write-wins for simple fields
- [ ] Implement merge logic for nested structures (e.g., karma scores)
- [ ] Create conflict detection by comparing local vs remote timestamps
- [ ] Implement user-facing conflict resolution UI for critical data
- [ ] VERIFY: Write unit tests for conflict resolution algorithms
- [ ] VERIFY: Write integration tests by simulating conflicting edits
- [ ] SECURITY CHECKPOINT: Confirm conflict resolution never exposes raw data to logs

### 5.6 Offline Queue Persistence
- [ ] Implement queue persistence across app restarts
- [ ] Create queue backup/restore mechanism
- [ ] Implement queue size limits (max 1000 items, FIFO eviction)
- [ ] Create queue cleanup for expired items (30 days)
- [ ] VERIFY: Write unit tests for queue persistence
- [ ] VERIFY: Write integration tests by restarting app during sync
- [ ] SECURITY CHECKPOINT: Confirm queued data remains encrypted at rest

---

## Phase 6: Pillar 1 — The Vault (Secure Messaging)

### Objective
Implement the Vault pillar with end-to-end encrypted messaging, connection requests, and zero-cloud-footprint architecture.

### 6.1 Vault UI Foundation
- [ ] Create `VaultMasthead` component with classified document aesthetic
- [ ] Implement conversation list screen with ciphertext previews
- [ ] Create conversation detail screen with message bubbles
- [ ] Implement connection request queue UI
- [ ] Apply `FLAG_SECURE` wrapper to all Vault screens
- [ ] VERIFY: Write widget tests for VaultMasthead rendering
- [ ] VERIFY: Write integration tests for conversation list navigation
- [ ] SECURITY CHECKPOINT: Confirm FLAG_SECURE is active on all Vault screens

### 6.2 Connection Request Flow
- [ ] Implement username search via API Gateway
- [ ] Create connection request sending logic
- [ ] Implement connection request receiving and approval UI
- [ ] Create Connection Request state machine in local database
- [ ] Implement cryptographic key exchange on approval
- [ ] VERIFY: Write unit tests for connection request state transitions
- [ ] VERIFY: Write integration tests for key exchange on approval
- [ ] SECURITY CHECKPOINT: Confirm connection requests never expose phone numbers

### 6.3 Message Encryption & Decryption
- [ ] Implement client-side message encryption using Signal Protocol
- [ ] Create message bubble UI with sent/received states
- [ ] Implement read receipt logic (✓ sent, ✓✓ delivered, ✓✓✓ read)
- [ ] Create message expiration logic (TTL-based deletion)
- [ ] Implement message queueing for offline send
- [ ] VERIFY: Write unit tests for message encryption/decryption
- [ ] VERIFY: Write integration tests for offline message queuing
- [ ] SECURITY CHECKPOINT: Confirm message content is never logged plaintext

### 6.4 WebSocket Message Relay
- [ ] Implement WebSocket client for real-time message delivery
- [ ] Create message envelope parsing logic
- [ ] Implement heartbeat/ping-pong for connection health
- [ ] Create reconnection logic with exponential backoff
- [ ] Implement dummy traffic for obfuscation (opt-in)
- [ ] VERIFY: Write integration tests for WebSocket connection lifecycle
- [ ] VERIFY: Write unit tests for heartbeat timeout handling
- [ ] SECURITY CHECKPOINT: Confirm WebSocket authentication uses JWT in body, not URL

### 6.5 Multi-Device Pairing
- [ ] Implement QR code generation for device pairing
- [ ] Create QR scanning logic for new device authorization
- [ ] Implement key transfer via QR (not cloud sync)
- [ ] Create device management UI (list linked devices, revoke)
- [ ] VERIFY: Write integration tests for QR-based pairing
- [ ] VERIFY: Write unit tests for device revocation
- [ ] SECURITY CHECKPOINT: Confirm device pairing never uses cloud backup

### 6.6 Duress PIN Integration
- [ ] Integrate duress PIN flow into Vault unlock
- [ ] Create decoy Vault UI (visually identical, empty)
- [ ] Implement duress PIN detection and database switching
- [ ] Create duress PIN setup flow during onboarding
- [ ] VERIFY: Write unit tests for duress PIN database switching
- [ ] VERIFY: Write integration tests for decoy Vault rendering
- [ ] SECURITY CHECKPOINT: Confirm duress PIN is indistinguishable from real PIN

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

**Current Phase:** Phase 1 - Environment & CI/CD Setup  
**Current Task:** 1.2 Infrastructure as Code (Terraform)  
**Overall Progress:** 1% (7/473 tasks completed)

**Last Updated:** 2026-07-04  
**Next Review:** After completion of Phase 1

---

## Change Log

| Date | Version | Changes |
|------|---------|---------|
| 2026-07-04 | 1.0 | Initial MASTER_PLAN creation |
| 2026-07-04 | 1.1 | Completed Phase 1.1 - Repository & Development Environment Setup |

