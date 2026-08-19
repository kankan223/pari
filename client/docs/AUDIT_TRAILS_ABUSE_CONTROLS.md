# Civic Commons — Audit Trails & Abuse Controls

**Document Version:** 1.0  
**Last Updated:** 2026-08-19  
**Status:** Complete  
**Phase:** 11.5 Compliance Documentation  

---

## 1. Executive Summary

Civic Commons implements comprehensive audit trails and abuse controls to ensure platform integrity, detect suspicious activity, and maintain compliance with security requirements. This document details the tamper-evident audit logging system and client-side rate limiting engine.

**Key Components:**
1. **SHA-256 Hash-Chained Audit Log** — Append-only, tamper-evident records
2. **Client-Side Rate Limiting** — Sliding-window throttling with cooldowns
3. **Abuse Detection** — Pattern-based suspicious activity detection

---

## 2. Audit Trail Architecture

### 2.1 Hash Chain Structure

```
┌─────────────────────────────────────────────────────────────┐
│                    AUDIT LOG CHAIN                           │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GENESIS                                                    │
│  │  prevHash = 000...000 (64 zeros)                        │
│  │                                                          │
│  ▼                                                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Record #0                                            │    │
│  │ seq: 0                                               │    │
│  │ action: CONSENT_GRANTED                              │    │
│  │ summary: "User granted consent for core functionality"│    │
│  │ timestamp: 2026-08-19T12:00:00Z                      │    │
│  │ prevHash: 000...000                                  │    │
│  │ selfHash: SHA-256(canonicalBytes)                    │    │
│  └─────────────────────────────────────────────────────┘    │
│  │                                                          │
│  │  prevHash = selfHash of Record #0                       │
│  ▼                                                          │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ Record #1                                            │    │
│  │ seq: 1                                               │    │
│  │ action: ACCOUNT_CREATED                              │    │
│  │ summary: "Account created via OTP verification"      │    │
│  │ timestamp: 2026-08-19T12:01:00Z                      │    │
│  │ prevHash: [selfHash of Record #0]                    │    │
│  │ selfHash: SHA-256(canonicalBytes)                    │    │
│  └─────────────────────────────────────────────────────┘    │
│  │                                                          │
│  │  ... chain continues                                     │
│  ▼                                                          │
│  [Future Records]                                           │
│                                                             │
│  TAMPER DETECTION:                                          │
│  - Modifying any record breaks all subsequent links         │
│  - verifyIntegrity() recomputes entire chain                │
│  - Any mismatch indicates tampering                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.2 Audit Record Structure

```dart
class AuditRecord {
  final int seq;              // Monotonic chain position (0-based)
  final String recordId;      // UUID v4 identifier
  final AuditAction action;   // Fixed wire code
  final String summary;       // Public, non-PII label
  final DateTime occurredAt;  // UTC timestamp
  final String prevHash;      // SHA-256 of previous record
  final String selfHash;      // SHA-256 of this record
}
```

### 2.3 Audit Actions (6 Fixed Types)

| Action | Label | Description |
|--------|-------|-------------|
| `consentGranted` | CONSENT GRANTED | User granted consent for a purpose |
| `consentWithdrawn` | CONSENT WITHDRAWN | User withdrew consent |
| `dataDeletionRequested` | DATA DELETION REQUESTED | User requested data deletion |
| `accountCreated` | ACCOUNT CREATED | New account registered |
| `credentialChanged` | CREDENTIAL CHANGED | Password/PIN changed |
| `sensitiveDataAccessed` | SENSITIVE DATA ACCESSED | Sensitive data was accessed |

### 2.4 Integrity Verification

```dart
Future<bool> verifyIntegrity() async {
  var expectedPrev = AuditRecord.genesisHash;
  
  for (final record in records) {
    // 1. Check sequence is in order
    if (record.seq != expectedIndex) return false;
    
    // 2. Check prevHash links to chain
    if (record.prevHash != expectedPrev) return false;
    
    // 3. Recompute selfHash
    final recomputed = await record.computeSelfHash(hasher);
    if (recomputed != record.selfHash) return false;
    
    // 4. Move to next
    expectedPrev = record.selfHash;
  }
  
  return true; // Chain is intact
}
```

---

## 3. Rate Limiting Architecture

### 3.1 Sliding Window Model

```
┌─────────────────────────────────────────────────────────────┐
│                    SLIDING WINDOW RATE LIMITING              │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  POLICY: OTP Request                                        │
│  Max Requests: 5                                            │
│  Window: 10 minutes                                         │
│  Cooldown: 15 minutes                                       │
│                                                             │
│  TIME ──────────────────────────────────────────────────>   │
│                                                             │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ WINDOW 1 (0-10 min)                                  │    │
│  │ Requests: [R1] [R2] [R3] [R4] [R5]                 │    │
│  │ Count: 5/5 (LIMIT REACHED)                          │    │
│  │ Status: COOLDOWN ACTIVE                              │    │
│  └─────────────────────────────────────────────────────┘    │
│       │                                                     │
│       │ Cooldown period (15 min)                            │
│       ▼                                                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │ WINDOW 2 (10-20 min)                                 │    │
│  │ Requests: [R6]                                       │    │
│  │ Count: 1/5                                           │    │
│  │ Status: ACTIVE                                       │    │
│  └─────────────────────────────────────────────────────┘    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Rate Limit Policies (8 Fixed Types)

| Policy | Max Requests | Window | Cooldown | Use Case |
|--------|--------------|--------|----------|----------|
| OTP Request | 5 | 10 min | 15 min | SMS bombing prevention |
| Login Attempt | 10 | 15 min | 30 min | Brute force prevention |
| Username Claim | 3 | 1 hour | 2 hours | Squatting prevention |
| Connection Request | 10 | 1 hour | 1 hour | Spam prevention |
| Post Creation | 20 | 1 hour | 30 min | Spam bot prevention |
| Vote Action | 100 | 1 hour | 15 min | Manipulation prevention |
| API Mutation | 30 | 5 min | 10 min | API abuse prevention |
| General Action | 60 | 1 min | 2 min | General throttling |

### 3.3 Rate Limit Bucket Structure

```dart
class RateLimitBucket {
  final RateLimitPolicy policy;
  final int requestCount;        // Current window count
  final DateTime windowStart;    // Window start time
  final bool cooldownActive;     // Whether in cooldown
  final DateTime? cooldownStartedAt;  // Cooldown start
  
  // Immutable operations
  RateLimitBucket withRequest(DateTime now);  // Increment
  RateLimitBucket withReset(DateTime now);    // Clear
  
  // Pure queries
  bool get isLimitReached;
  bool isWindowExpired(DateTime now);
  bool isCooldownExpired(DateTime now);
  int get remainingRequests;
  int cooldownRemainingSeconds(DateTime now);
}
```

---

## 4. Abuse Detection

### 4.1 Abuse Triggers (8 Fixed Types)

| Trigger | Severity | Description |
|---------|----------|-------------|
| `excessiveOtpRequests` | HIGH | Too many OTP requests in short period |
| `rapidLoginFailures` | HIGH | Multiple failed login attempts |
| `lockstepVoting` | MEDIUM | Multiple new accounts voting together |
| `excessiveConnectionRequests` | MEDIUM | Too many connection requests |
| `rapidPostCreation` | LOW | Unusually fast post creation |
| `credentialStuffing` | CRITICAL | Pattern of login attempts with different credentials |
| `apiAbuse` | HIGH | Excessive API mutation requests |
| `accountEnumeration` | MEDIUM | Attempts to discover valid accounts |

### 4.2 Severity Levels

| Level | Label | Action |
|-------|-------|--------|
| LOW | LOW | Informational, no immediate action |
| MEDIUM | MEDIUM | Monitoring increased, possible throttling |
| HIGH | HIGH | Immediate rate limiting, cooldown enforced |
| CRITICAL | CRITICAL | Temporary account suspension recommended |

### 4.3 Abuse Event Structure

```dart
class AbuseEvent {
  final String eventId;        // UUID v4 identifier
  final AbuseTrigger trigger;  // Fixed trigger type
  final DateTime detectedAt;   // When detected (UTC)
  final int occurrenceCount;   // Number of occurrences
}
```

---

## 5. Implementation Details

### 5.1 Schema (v18-19)

```sql
-- Audit Events (v18)
CREATE TABLE audit_events (
    record_id TEXT PRIMARY KEY NOT NULL,
    seq INTEGER NOT NULL,
    action TEXT NOT NULL,
    summary TEXT NOT NULL,
    occurred_at INTEGER NOT NULL,
    prev_hash TEXT NOT NULL,
    self_hash TEXT NOT NULL
);
-- ZERO identity columns

-- Rate Limit Buckets (v19)
CREATE TABLE rate_limit_buckets (
    policy TEXT PRIMARY KEY NOT NULL,
    request_count INTEGER NOT NULL,
    window_start INTEGER NOT NULL,
    cooldown_active INTEGER NOT NULL,
    cooldown_started_at INTEGER
);
-- ZERO identity columns

-- Abuse Events (v19)
CREATE TABLE abuse_events (
    event_id TEXT PRIMARY KEY NOT NULL,
    trigger_type TEXT NOT NULL,
    severity TEXT NOT NULL,
    detected_at INTEGER NOT NULL,
    occurrence_count INTEGER NOT NULL
);
-- ZERO identity columns
```

### 5.2 Repository APIs

```dart
// Audit Repository (APPEND-ONLY)
abstract class AuditRepository {
  Future<List<AuditRecord>> getAll();
  Future<int> getCount();
  Future<void> append(AuditRecord record);
  Future<bool> verifyIntegrity();
}

// Rate Limit Repository
abstract class RateLimitRepository {
  Future<RateLimitBucket> getBucket(RateLimitPolicy policy);
  Future<RateLimitBucket> recordRequest(RateLimitPolicy policy);
  Future<List<AbuseEvent>> getAbuseEvents({DateTime? since});
  Future<void> recordAbuseEvent(AbuseEvent event);
  Future<int> getAbuseEventCount();
}
```

### 5.3 State Management

```dart
// Audit Log State
class AuditLogState {
  final AuditLogPhase phase;
  final List<AuditRecord> records;
  final bool integrityValid;
  final int recordCount;
}

// Rate Limit State
class RateLimitState {
  final RateLimitPhase phase;
  final Map<String, RateLimitBucket> buckets;
  final List<AbuseEvent> abuseEvents;
  final int totalAbuseEvents;
}
```

---

## 6. Security Properties

### 6.1 Tamper Evidence

| Property | Mechanism |
|----------|-----------|
| Append-only | No update/delete API in repository |
| Chain integrity | SHA-256 hash links (prevHash → selfHash) |
| Verification | `verifyIntegrity()` recomputes entire chain |
| Detection | Any modification breaks subsequent links |

### 6.2 Zero-PII Guarantee

| Component | Identity Fields | Status |
|-----------|-----------------|--------|
| AuditRecord | 0 (action + summary + timestamp only) | ✅ |
| RateLimitBucket | 0 (policy + count + timestamp only) | ✅ |
| AbuseEvent | 0 (trigger + severity + timestamp only) | ✅ |
| audit_events table | 0 | ✅ |
| rate_limit_buckets table | 0 | ✅ |
| abuse_events table | 0 | ✅ |

### 6.3 Local-First Operation

- All rate limiting is client-side
- No network calls required for throttling
- Abuses detected locally before sync
- Works fully offline

---

## 7. Verification & Testing

### 7.1 Test Coverage

| Component | Tests | Status |
|-----------|-------|--------|
| Audit Actions | 6 | ✅ |
| Audit Records | 8 | ✅ |
| Audit Repository | 10 | ✅ |
| Audit Codec | 4 | ✅ |
| Rate Limit Policies | 12 | ✅ |
| Rate Limit Buckets | 12 | ✅ |
| Rate Limit Repository | 10 | ✅ |
| Rate Limit Codec | 7 | ✅ |
| Abuse Triggers | 22 | ✅ |
| State Tests | 11 | ✅ |
| Bloc Tests | 13 | ✅ |
| Widget Tests | 5 | ✅ |
| Security Checkpoints | 16 | ✅ |
| **Total** | **136** | **✅ All pass** |

### 7.2 Security Checkpoints

✅ No networking imports in audit/rate_limit domain  
✅ No print/debugPrint in production code  
✅ Zero identity columns in all tables  
✅ FLAG_SECURE on audit/rate_limit screens  
✅ Append-only audit log (no update/delete)  
✅ SHA-256 chain integrity verified  
✅ Client-side rate limiting (no network dependency)  

---

## 8. Compliance Verification Commands

```bash
# Run audit tests
flutter test test/audit/

# Run rate limit tests
flutter test test/rate_limit/

# Run security checkpoints
flutter test test/audit/security_checkpoint_test.dart
flutter test test/rate_limit/security_checkpoint_test.dart

# Verify chain integrity
flutter test test/audit/in_memory_audit_repository_test.dart

# Verify rate limiting
flutter test test/rate_limit/rate_limit_bucket_test.dart
```

---

## 9. Document History

| Date | Version | Changes |
|------|---------|---------|
| 2026-08-19 | 1.0 | Initial Audit Trails & Abuse Controls for Task 11.5 |

---

**Document Classification:** Internal — Security Architecture  
**Owner:** Security Team  
**Review Cycle:** Quarterly or upon architecture changes
