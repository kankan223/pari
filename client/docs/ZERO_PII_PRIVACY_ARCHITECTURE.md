# Civic Commons — Zero-PII & Privacy Architecture

**Document Version:** 1.0  
**Last Updated:** 2026-08-19  
**Status:** Complete  
**Phase:** 11.5 Compliance Documentation  

---

## 1. Executive Summary

Civic Commons implements a comprehensive Zero-PII (Personally Identifiable Information) architecture that ensures no raw personal data ever leaves the device, is stored in plaintext, or is exposed through UI, logs, or network communications. This document details the architectural patterns, implementation details, and verification mechanisms that enforce this privacy guarantee.

**Core Principle:** The platform operates on blind hashes and pseudonymous handles — never on raw identities.

---

## 2. Identity Model

### 2.1 Blind Hash Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    IDENTITY MODEL                            │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  RAW PHONE NUMBER (E.164)                                   │
│       │                                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Argon2id(phone + salt)                              │    │
│  │ Memory: 64 MiB, Iterations: 3, Parallelism: 4      │    │
│  │ Salt: Fetched from Vault, never stored locally      │    │
│  └─────────────────────────────────────────────────────┘    │
│       │                                                     │
│       ▼                                                     │
│  64-HEX BLIND HASH ID (blind_hash_id)                      │
│       │                                                     │
│       ├──> users.blind_hash_id                              │
│       ├──> conversations.participant_hash                   │
│       ├──> messages.ciphertext (encrypted)                  │
│       ├──> connection_requests.requester_hash               │
│       ├──> devices.blind_hash                               │
│       ├──> karma_events.actor_hash                          │
│       └──> [All other tables]                               │
│                                                             │
│  RAW PHONE EXISTS ONLY:                                     │
│  - Inside the request handler (milliseconds)                │
│  - Hashed immediately via Argon2id                          │
│  - Buffer zeroed after hashing                              │
│  - Never persisted, never logged, never transmitted         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Pseudonymous Handles

| Handle | Format | Usage | Identity? |
|--------|--------|-------|-----------|
| `@peer_XXXXXX` | `@peer_` + 6-hex | Vault peer display | ❌ No |
| `@citizen_XXXXXX` | `@citizen_` + 6-hex | Identity display | ❌ No |
| `DEV_XXXXXX` | `DEV_` + 6-hex | Device display | ❌ No |
| `SG-####` | `SG-` + 4-hex | Study group member | ❌ No |
| `SA-####` | `SA-` + 4-hex | Sandbox author | ❌ No |
| `AN-####` | `AN-` + 4-hex | War Room analyst | ❌ No |

**All handles are derived from UUIDs or blind hashes — never from raw identities.**

---

## 3. Schema Zero-PII Verification

### 3.1 Complete Table Inventory

| # | Table | Identity Columns | Status |
|---|-------|------------------|--------|
| 1 | users | 0 (blind_hash_id only) | ✅ |
| 2 | conversations | 0 (participant_hash only) | ✅ |
| 3 | messages | 0 (ciphertext only) | ✅ |
| 4 | connection_requests | 0 (hashes only) | ✅ |
| 5 | sync_queue | 0 (payload only) | ✅ |
| 6 | devices | 0 (blind_hash only) | ✅ |
| 7 | ledger_drafts | 0 | ✅ |
| 8 | post_votes | 0 | ✅ |
| 9 | peer_reviews | 0 | ✅ |
| 10 | evidence | 0 | ✅ |
| 11 | intake_drafts | 0 | ✅ |
| 12 | academy_domains | 0 | ✅ |
| 13 | academy_modules | 0 | ✅ |
| 14 | academy_progress | 0 | ✅ |
| 15 | module_cache | 0 | ✅ |
| 16 | sandbox_pages | 0 | ✅ |
| 17 | sandbox_revisions | 0 | ✅ |
| 18 | study_groups | 0 | ✅ |
| 19 | study_group_members | 0 | ✅ |
| 20 | karma_events | 0 | ✅ |
| 21 | notifications | 0 | ✅ |
| 22 | transparency_events | 0 | ✅ |
| 23 | consent_records | 0 | ✅ |
| 24 | audit_events | 0 | ✅ |
| 25 | rate_limit_buckets | 0 | ✅ |
| 26 | abuse_events | 0 | ✅ |

**Total Identity Columns:** 0/26 tables ✅

### 3.2 Identity Columns Scanned

The following column names are forbidden in all tables:
- `phone`, `email`, `user_id`, `user_name`
- `full_name`, `first_name`, `last_name`
- `address`, `date_of_birth`
- `national_id`, `aadhaar`, `pan`, `ssn`

---

## 4. Local-First Storage Architecture

### 4.1 SQLCipher Encryption

```
┌─────────────────────────────────────────────────────────────┐
│                    STORAGE LAYER                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │                 SQLCipher Database                    │    │
│  │                 (AES-256-GCM Encryption)             │    │
│  │                                                      │    │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐ │    │
│  │  │   users     │  │  messages   │  │  evidence   │ │    │
│  │  │   (26 tbls) │  │  (ciphertext)│  │  (sealed)   │ │    │
│  │  └─────────────┘  └─────────────┘  └─────────────┘ │    │
│  │                                                      │    │
│  │  Key: Argon2id derived from user PIN                 │    │
│  │  Never stored, never logged, never transmitted       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              AES-256-GCM Queue Payloads              │    │
│  │                                                      │    │
│  │  sync_queue.payload = AES-GCM(plaintext, key)       │    │
│  │  Key: Per-device DEK                                │    │
│  │  Stored: Ciphertext only                            │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │              Evidence File Encryption                │    │
│  │                                                      │    │
│  │  sealed_file = AES-GCM(file_bytes, DEK)             │    │
│  │  dek_envelope = X25519-wrap(DEK, public_key)        │    │
│  │  DEK: Never stored plaintext                        │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 4.2 Data Flow: Offline-First

```
┌─────────────────────────────────────────────────────────────┐
│                OFFLINE-FIRST DATA FLOW                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. USER ACTION                                              │
│     └─> Create post / Send message / Submit evidence        │
│                                                             │
│  2. LOCAL PERSISTENCE (FIRST)                                │
│     └─> Write to SQLCipher encrypted database               │
│     └─> Data encrypted at rest immediately                  │
│     └─> App functions fully offline                         │
│                                                             │
│  3. QUEUE ENVELOPE                                           │
│     └─> Serialize data to wire format                       │
│     └─> Seal with AES-256-GCM                              │
│     └─> Store sealed payload in sync_queue                  │
│                                                             │
│  4. SYNC (WHEN CONNECTED)                                    │
│     └─> Background worker drains queue                      │
│     └─> Sends sealed envelope to server                     │
│     └─> Server never sees plaintext                         │
│                                                             │
│  5. ACKNOWLEDGEMENT                                          │
│     └─> Server confirms receipt                             │
│     └─> Queue item deleted                                  │
│     └─> Local state updated                                 │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 5. Memory Hygiene

### 5.1 Buffer Wipe Routines

| Component | Wipe Method | Trigger |
|-----------|-------------|---------|
| Phone input buffer | `zeroFill()` | After Argon2id hash |
| OTP code buffer | `zeroFill()` | After verification |
| PIN input controllers | `clear()` | After authentication |
| Intake narrative buffer | `zeroFill()` | Quick Exit / Submit |
| Evidence file buffers | `zeroFill()` | After encryption |
| Crypto key material | `WipeBytes()` | Cache rotation |

### 5.2 Quick Exit Wipe

```
┌─────────────────────────────────────────────────────────────┐
│                    QUICK EXIT WIPE                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  User taps "Quick Exit"                                     │
│       │                                                     │
│       ▼                                                     │
│  1. Clear all text controllers                              │
│  2. Zero-fill evidence byte buffers                         │
│  3. Drop picked file selections                             │
│  4. Clear intake draft state                                │
│  5. Navigate to neutral safe screen                         │
│                                                             │
│  Result: All transient PII erased from memory               │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 6. Network Privacy

### 6.1 Sealed Sync Protocol

```
┌─────────────────────────────────────────────────────────────┐
│                    SEALED SYNC PROTOCOL                      │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CLIENT DEVICE                                              │
│       │                                                     │
│       │  Plaintext data                                     │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  QueuePayloadCipher                                  │    │
│  │  AES-256-GCM(plaintext, device_key)                 │    │
│  └─────────────────────────────────────────────────────┘    │
│       │                                                     │
│       │  Sealed ciphertext                                 │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  sync_queue.payload                                  │    │
│  │  (ciphertext only)                                   │    │
│  └─────────────────────────────────────────────────────┘    │
│       │                                                     │
│       │  HTTP POST with sealed payload                      │
│       ▼                                                     │
│  SERVER (sees only ciphertext)                              │
│       │                                                     │
│       │  Never decrypts, routes opaque                      │
│       ▼                                                     │
│  RECIPIENT DEVICE                                           │
│       │                                                     │
│       ▼                                                     │
│  Decrypt with shared key                                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 6.2 IP Address Stripping

- Kong gateway strips `X-Forwarded-For` header
- `civic-strip-peer-ip` plugin zeroes upstream variables
- Upstream receives NO client IP information

### 6.3 PII Log Scrubbing

- `civic-pii-access-log` plugin scrubs:
  - E.164 phone numbers (including URL-encoded `%2B`)
  - IPv4/IPv6 addresses
  - Email addresses
  - 64-hex blind hash IDs

---

## 7. Verification & Testing

### 7.1 Automated Checks

| Check | Method | Result |
|-------|--------|--------|
| Schema zero-PII | Static column scan | ✅ 26/26 tables |
| No networking in domain | Import scan | ✅ 0 violations |
| No print/debugPrint | Code scan | ✅ 0 violations |
| FLAG_SECURE on screens | Widget tree scan | ✅ 11/11 screens |
| No hardcoded secrets | Pattern scan | ✅ 0 violations |
| Sealed payloads | Byte-level proof | ✅ Verified |

### 7.2 Test Coverage

- **Security Audit Suite:** 19 tests
- **Per-Module Checkpoints:** 37 tests
- **Total Security Tests:** 56 tests
- **All passing:** ✅

### 7.3 Runtime Verification

| Test | Method | Result |
|------|--------|--------|
| Phone never persisted | Redis dump scan | ✅ No phone in keys/values |
| Phone never logged | Log buffer scan | ✅ No phone in logs |
| Ciphertext byte-identical | Round-trip comparison | ✅ Verified |
| Sealed payload != plaintext | Byte comparison | ✅ Verified |

---

## 8. Compliance Verification Commands

```bash
# Check schema for identity columns
grep -r "phone\|email\|user_id" lib/database/domain/schema.dart
# Expected: 0 results (excluding comments)

# Check domain for networking
grep -r "import.*dart:io\|import.*package:http" lib/*/domain/
# Expected: 0 results

# Check for print statements
grep -r "print(\|debugPrint(" lib/ --include="*.dart" | grep -v test
# Expected: 0 results

# Check FLAG_SECURE on screens
grep -r "SecureScreenWrapper" lib/state/ui/
# Expected: 11+ results

# Run security tests
flutter test test/security/
# Expected: 19 tests passed
```

---

## 9. Document History

| Date | Version | Changes |
|------|---------|---------|
| 2026-08-19 | 1.0 | Initial Zero-PII & Privacy Architecture for Task 11.5 |

---

**Document Classification:** Confidential — Privacy Architecture  
**Owner:** Privacy & Security Team  
**Review Cycle:** Quarterly or upon architecture changes
