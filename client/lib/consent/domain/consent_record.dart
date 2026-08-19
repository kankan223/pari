import 'consent_type.dart';

/// Immutable DPDP consent record (Task 11.1 — DPDP Consent Implementation).
///
/// Tracks the user's consent status for each data processing purpose.
/// The record is append-only — new records are created when consent is
/// granted or withdrawn, forming an audit trail.
///
/// SECURITY CHECKPOINT (11.1): records carry ONLY the consent type,
/// version, status, and timestamps. No phone numbers, no blind hashes,
/// no identity fields.
class ConsentRecord {
  /// UUID v4 identifier for this consent record.
  final String recordId;

  /// The type of consent (purpose).
  final ConsentType type;

  /// The version of the consent text the user agreed to.
  final String consentVersion;

  /// Whether consent is currently granted or withdrawn.
  final bool granted;

  /// Timestamp when consent was granted or withdrawn (UTC).
  final DateTime timestamp;

  /// The consent text hash (SHA-256 of the consent document at the
  /// version the user agreed to) for tamper evidence.
  final String textHash;

  const ConsentRecord({
    required this.recordId,
    required this.type,
    required this.consentVersion,
    required this.granted,
    required this.timestamp,
    required this.textHash,
  });

  /// Returns a copy with consent withdrawn.
  ConsentRecord withdraw() => ConsentRecord(
        recordId: recordId,
        type: type,
        consentVersion: consentVersion,
        granted: false,
        timestamp: DateTime.now().toUtc(),
        textHash: textHash,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ConsentRecord &&
          runtimeType == other.runtimeType &&
          recordId == other.recordId &&
          granted == other.granted;

  @override
  int get hashCode => recordId.hashCode ^ granted.hashCode;
}
