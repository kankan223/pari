import '../../audit/domain/audit_record.dart';

/// Audit log phases (Task 11.2).
enum AuditLogPhase {
  /// Not started.
  idle,

  /// Loading audit records.
  loading,

  /// Audit log is ready for display.
  ready,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Immutable state projection for the Audit Log (Task 11.2).
///
/// Carries the list of audit records, integrity status, and record count.
///
/// SECURITY CHECKPOINT (11.2): the state carries only public-label summaries
/// and fixed action labels — no phone numbers, no blind hashes, no identity
/// fields.
class AuditLogState {
  final AuditLogPhase phase;
  final List<AuditRecord> records;
  final bool integrityValid;
  final int recordCount;
  final String? errorMessage;

  const AuditLogState({
    this.phase = AuditLogPhase.idle,
    this.records = const [],
    this.integrityValid = true,
    this.recordCount = 0,
    this.errorMessage,
  });
}
