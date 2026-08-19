# Civic Commons — DPDP Act Compliance Matrix

**Document Version:** 1.0  
**Last Updated:** 2026-08-19  
**Status:** Complete  
**Phase:** 11.5 Compliance Documentation  

---

## 1. Executive Summary

Civic Commons complies with India's Digital Personal Data Protection Act (DPDP) 2023 through a comprehensive consent management system, data minimization practices, and automated data deletion workflows. This document details the compliance posture across all required dimensions.

---

## 2. Consent Lifecycle Management

### 2.1 Consent Types (5 Fixed Categories)

| Type | Wire Name | Required | Description |
|------|-----------|----------|-------------|
| **Core Functionality** | `core_functionality` | ✅ Required | Identity verification, messaging, and account management |
| **Civic Engagement** | `civic_engagement` | ✅ Required | Posting, voting, and peer review on the Daily Ledger |
| **Security Contributions** | `security_contributions` | ✅ Required | Submitting evidence to the War Room for investigation |
| **Educational Content** | `educational_content` | ✅ Required | Accessing Academy modules, study groups, and learning resources |
| **Analytics & Improvement** | `analytics` | ❌ Optional | Anonymized usage analytics for platform improvement |

### 2.2 Consent Record Structure

Each consent record is an immutable entity with:
- **UUID v4 record ID** — unique, non-sequential identifier
- **Consent Type** — fixed wire name from the 5 categories above
- **Consent Version** — version string (currently "1.0") tied to the consent text
- **Granted Status** — boolean flag (true = granted, false = withdrawn)
- **Timestamp** — UTC timestamp of the grant/withdrawal event
- **Text Hash** — SHA-256 hash of the consent document for tamper evidence

### 2.3 Consent Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    CONSENT LIFECYCLE                         │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1. ONBOARDING                                              │
│     └─> Display consent form with 5 purposes                │
│     └─> User toggles each purpose (required pre-checked)    │
│     └─> All required consents must be granted               │
│     └─> ConsentRecord created for each type                 │
│                                                             │
│  2. GRANT                                                   │
│     └─> User enables a consent toggle                       │
│     └─> New ConsentRecord with granted=true                 │
│     └─> SHA-256 hash of consent text stored                 │
│                                                             │
│  3. WITHDRAWAL                                              │
│     └─> User disables a consent toggle                      │
│     └─> New ConsentRecord with granted=false                │
│     └─> Original record unchanged (append-only)             │
│                                                             │
│  4. DATA DELETION (DPDP §8)                                 │
│     └─> User triggers "Withdraw All Consents"               │
│     └─> All consent records marked withdrawn                │
│     └─> deleteUserData() clears consent records             │
│     └─> onDataDeleted callback triggered                    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### 2.4 Consent Versioning

- Consent version string is currently `"1.0"`
- Version bumped when consent text changes
- Each record stores the version the user agreed to
- `ConsentRecord.textHash` provides tamper evidence for the consent document

### 2.5 Required vs Optional Consent

| Category | Required | Rationale |
|----------|----------|-----------|
| Core Functionality | Yes | Essential for platform operation |
| Civic Engagement | Yes | Core purpose of the platform |
| Security Contributions | Yes | Enables War Room functionality |
| Educational Content | Yes | Enables Academy functionality |
| Analytics | No | Enhancement only, not essential |

**Enforcement:** `hasAllRequiredConsents()` returns true only when all 4 required consents are granted. The analytics consent is excluded from this check.

---

## 3. Data Subject Rights (DPDP §5-8)

### 3.1 Right to Access (§5)

- Users can view all consent records via the Consent UI
- `getConsent(type)` returns the current consent status per purpose
- `getAllConsents()` returns the complete consent history

### 3.2 Right to Withdraw Consent (§6)

- Users can withdraw consent at any time via toggle switches
- Withdrawal is recorded as a new append-only record
- No data processing occurs after withdrawal for the withdrawn purpose

### 3.3 Right to Data Deletion (§7-8)

- `deleteUserData()` clears all consent records
- `onDataDeleted` callback triggers platform-wide data removal
- Deletion phases tracked: `idle → deleting → deleted`

### 3.4 Right to Grievance Redressal

- Audit log records all consent grants/withdrawals/deletions
- Tamper-evident SHA-256 hash chain prevents log manipulation
- All actions timestamped and non-repudiable

---

## 4. Data Processing Purposes

| Purpose | Data Processed | Retention | Deletion Trigger |
|---------|---------------|-----------|------------------|
| Core Functionality | Blind hash ID, username, device keys | Account lifetime | Account deletion |
| Civic Engagement | Post content, votes, reviews | 7 years | User deletion |
| Security Contributions | Evidence files (encrypted), case metadata | Case lifetime | Case closure + retention |
| Educational Content | Module progress, study groups | Account lifetime | User deletion |
| Analytics | Anonymized usage metrics | 90 days | Automatic expiry |

---

## 5. Technical Implementation

### 5.1 Schema (v17: `consent_records`)

```sql
CREATE TABLE consent_records (
    record_id TEXT PRIMARY KEY NOT NULL,  -- UUID v4
    type TEXT NOT NULL,                   -- Fixed wire name
    consent_version TEXT NOT NULL,        -- Version string
    granted INTEGER NOT NULL,             -- Boolean flag
    timestamp INTEGER NOT NULL,           -- UTC epoch ms
    text_hash TEXT NOT NULL               -- SHA-256 of consent doc
);
-- ZERO identity columns
```

### 5.2 Repository API

```dart
abstract class ConsentRepository {
  Future<ConsentRecord?> getConsent(ConsentType type);
  Future<List<ConsentRecord>> getAllConsents();
  Future<bool> hasConsent(ConsentType type);
  Future<void> grantConsent(ConsentType type);
  Future<void> withdrawConsent(ConsentType type);
  Future<bool> hasAllRequiredConsents();
  Future<void> deleteUserData();
}
```

### 5.3 State Management

```dart
class ConsentState {
  final ConsentPhase phase;  // idle/loading/ready/error/deleting/deleted
  final Map<ConsentType, bool> consentStatus;
  final bool allRequiredGranted;
  final String consentVersion;
  final String? errorMessage;
}
```

### 5.4 UI Components

- **DpdpConsentScreen** — FLAG_SECURE wrapped consent management screen
- Per-type toggle switches with required/optional labels
- Withdrawal confirmation dialog with DPDP §8 notice
- All Required Consents status banner
- Delete User Data button with confirmation

---

## 6. Security & Privacy

### 6.1 Zero-PII Guarantee

- Consent records carry ONLY: type, version, boolean, timestamp, hash
- No phone numbers, emails, or identity fields in schema
- No PII in UI renders, state projections, or logs

### 6.2 Tamper Evidence

- `textHash` = SHA-256 of consent document at agreed version
- Append-only record creation (no updates/deletes)
- Audit log tracks all consent operations

### 6.3 Encryption at Rest

- SQLCipher encrypts the entire database file
- Consent records in the encrypted partition

### 6.4 Secure Display

- FLAG_SECURE on consent screens (prevents screenshots)
- No PII in tooltips, error messages, or debug logs

---

## 7. Verification & Testing

### 7.1 Test Coverage

- **5 consent-type tests** — enum count, wire round-trip, labels, unknown/empty throws
- **5 consent-record tests** — construct, withdraw-copy, original-unchanged, equality
- **10 repository tests** — CRUD operations, required consent checks, deletion
- **7 codec tests** — encode/decode round-trip, missing columns, unknown types
- **9 state tests** — phase transitions, consent status, error handling
- **11 bloc tests** — lifecycle, grant/withdraw/delete flows
- **8 widget tests** — UI rendering, toggles, FLAG_SECURE
- **8 security tests** — no networking imports, no PII, FLAG_SECURE
- **Schema +1** — consent_records table validation
- **Migration +1** — v17 upgrade/rollback

### 7.2 Security Checkpoints

✅ No networking imports in consent domain/data/UI  
✅ No print/debugPrint in production code  
✅ Zero identity columns in consent_records table  
✅ FLAG_SECURE on DpdpConsentScreen  
✅ No PII in consent records (only type + boolean + timestamp + hash)  
✅ SHA-256 tamper evidence via textHash  
✅ Append-only record creation  

---

## 8. Compliance Verification Commands

```bash
# Run consent tests
flutter test test/consent/

# Run schema tests
flutter test test/database/schema_test.dart

# Run migration tests
flutter test test/database/migration_test.dart

# Static analysis
flutter analyze

# Check for PII in consent files
grep -r "phone\|email\|user_id" lib/consent/
# Expected: 0 results (excluding comments)
```

---

## 9. Document History

| Date | Version | Changes |
|------|---------|---------|
| 2026-08-19 | 1.0 | Initial DPDP Compliance Matrix for Task 11.5 |

---

**Document Classification:** Internal — Security & Compliance  
**Owner:** Engineering Team  
**Review Cycle:** Quarterly or upon regulatory changes
