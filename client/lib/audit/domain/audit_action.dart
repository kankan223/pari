/// Fixed audit event types for the Audit Logging System (Task 11.2).
///
/// Each action represents a sensitive operation that must be logged for
/// compliance and tamper-evident audit trails. The labels are fixed,
/// non-sensitive, and carry no PII.
///
/// SECURITY CHECKPOINT (11.2): actions carry NO identity, NO phone
/// numbers, NO payload content — they are fixed, compile-time-known
/// labels only.
enum AuditAction {
  consentGranted('CONSENT GRANTED', 'Consent'),
  consentWithdrawn('CONSENT WITHDRAWN', 'Withdrawal'),
  dataDeletionRequested('DATA DELETION REQUESTED', 'Deletion'),
  accountCreated('ACCOUNT CREATED', 'Account'),
  credentialChanged('CREDENTIAL CHANGED', 'Credential'),
  sensitiveDataAccessed('SENSITIVE DATA ACCESSED', 'Access');

  const AuditAction(this.label, this.shortLabel);

  /// Fixed, non-sensitive classification label rendered in the log viewer.
  final String label;

  /// Short display label for compact UI rendering.
  final String shortLabel;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static AuditAction fromWireName(String wire) {
    return AuditAction.values.firstWhere(
      (a) => a.name == wire,
      orElse: () => throw FormatException('Unknown audit action: $wire'),
    );
  }
}
