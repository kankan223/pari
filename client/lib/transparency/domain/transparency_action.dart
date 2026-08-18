/// Fixed transparency action types (Task 10.5 Transparency Log).
///
/// Each action represents a system or moderation event that is publicly
/// auditable. The labels are fixed, non-sensitive, and carry no PII.
///
/// SECURITY CHECKPOINT (10.5): actions carry NO identity, NO phone
/// numbers, NO payload content — they are fixed, compile-time-known
/// labels only.
enum TransparencyAction {
  moderationAction('MODERATION ACTION', 'Moderation'),
  contentReview('CONTENT REVIEW', 'Review'),
  accessRequest('ACCESS REQUEST', 'Access'),
  dataExport('DATA EXPORT', 'Export'),
  accountAction('ACCOUNT ACTION', 'Account'),
  systemEvent('SYSTEM EVENT', 'System');

  const TransparencyAction(this.label, this.shortLabel);

  /// Fixed, non-sensitive classification label rendered in the log viewer.
  final String label;

  /// Short display label for compact UI rendering.
  final String shortLabel;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static TransparencyAction fromWireName(String wire) {
    return TransparencyAction.values.firstWhere(
      (a) => a.name == wire,
      orElse: () => throw FormatException('Unknown transparency action: $wire'),
    );
  }
}
