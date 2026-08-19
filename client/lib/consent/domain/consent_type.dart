/// DPDP consent types for data processing purposes (Task 11.1).
///
/// Each type represents a specific purpose for which the platform
/// processes personal data. Users must explicitly consent to each
/// purpose before any data processing begins.
///
/// SECURITY CHECKPOINT (11.1): consent types carry NO identity, NO phone
/// numbers, NO payload content — they are fixed, compile-time-known
/// labels only.
enum ConsentType {
  /// Core platform functionality: identity verification, messaging,
  /// and account management.
  coreFunctionality('core_functionality', 'Core Platform Functionality',
      'Identity verification, messaging, and account management'),

  /// Civic engagement: posting to the Daily Ledger, voting, and
  /// peer review.
  civicEngagement('civic_engagement', 'Civic Engagement',
      'Posting, voting, and peer review on the Daily Ledger'),

  /// Security contributions: submitting evidence to the War Room
  /// for civic-issue investigation.
  securityContributions('security_contributions', 'Security Contributions',
      'Submitting evidence to the War Room for investigation'),

  /// Educational content: accessing Academy modules and study groups.
  educationalContent('educational_content', 'Educational Content',
      'Accessing Academy modules, study groups, and learning resources'),

  /// Analytics and improvement: anonymized usage analytics for
  /// platform improvement (optional).
  analytics('analytics', 'Analytics & Improvement',
      'Anonymized usage analytics for platform improvement');

  const ConsentType(this.wireName, this.label, this.description);

  /// Wire-stable string code for serialization.
  final String wireName;

  /// Short display label for UI rendering.
  final String label;

  /// Longer description explaining the purpose.
  final String description;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static ConsentType fromWireName(String wire) {
    return ConsentType.values.firstWhere(
      (t) => t.wireName == wire,
      orElse: () => throw FormatException('Unknown consent type: $wire'),
    );
  }
}
