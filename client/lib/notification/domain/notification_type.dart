/// The three Civic Commons notification types (Task 10.4 Notification System).
///
/// Each type maps to a specific pillar event that may trigger a push or
/// in-app notification. The type determines the icon, default preference
/// state, and routing target when the user taps the notification.
///
/// SECURITY CHECKPOINT (10.4): types carry NO identity, NO phone numbers,
/// and NO payload content — they are fixed, compile-time-known labels only.
enum NotificationType {
  /// A karma balance change: +5 for a verified Ledger post, −3 for a
  /// rejection, etc. The payload carries only the fixed action label
  /// and the integer delta — never the actor's blind hash.
  karmaEvent('karma_event', 'Karma'),

  /// A War Room case has been assigned to the current user (analyst
  /// vetting passed). The payload carries the case number and severity
  /// label — never victim identity or evidence content.
  caseAssignment('case_assignment', 'Case'),

  /// A Ledger post requires peer review. The payload carries the post
  /// headline and category — never the author's blind hash.
  ledgerReviewRequest('ledger_review_request', 'Ledger');

  /// Wire-stable string code for serialization.
  final String wireName;

  /// Short display label for UI rendering.
  final String label;

  const NotificationType(this.wireName, this.label);

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static NotificationType fromWireName(String wire) {
    return NotificationType.values.firstWhere(
      (t) => t.wireName == wire,
      orElse: () => throw FormatException('Unknown notification type: $wire'),
    );
  }
}
