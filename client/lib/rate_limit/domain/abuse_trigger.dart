/// Fixed abuse prevention trigger types (Task 11.3).
///
/// Each trigger represents a pattern of suspicious activity that must be
/// detected and mitigated. The labels are fixed, non-sensitive, and carry
/// no PII.
///
/// SECURITY CHECKPOINT (11.3): triggers carry NO identity, NO phone
/// numbers, NO payload content — they are fixed, compile-time-known
/// classifications only.
enum AbuseTrigger {
  /// Excessive OTP requests (potential SMS bombing).
  excessiveOtpRequests(
    label: 'Excessive OTP Requests',
    severity: AbuseSeverity.high,
    description: 'Too many OTP requests in a short period',
  ),

  /// Rapid login failures (potential brute-force).
  rapidLoginFailures(
    label: 'Rapid Login Failures',
    severity: AbuseSeverity.high,
    description: 'Multiple failed login attempts in quick succession',
  ),

  /// Lockstep voting (potential Sybil attack).
  lockstepVoting(
    label: 'Lockstep Voting',
    severity: AbuseSeverity.medium,
    description: 'Multiple new accounts voting within a short window',
  ),

  /// Excessive connection requests (potential spam).
  excessiveConnectionRequests(
    label: 'Excessive Connection Requests',
    severity: AbuseSeverity.medium,
    description: 'Too many connection requests in a short period',
  ),

  /// Rapid post creation (potential spam bot).
  rapidPostCreation(
    label: 'Rapid Post Creation',
    severity: AbuseSeverity.low,
    description: 'Unusually fast post creation rate',
  ),

  /// Credential stuffing attempt.
  credentialStuffing(
    label: 'Credential Stuffing',
    severity: AbuseSeverity.critical,
    description: 'Pattern of login attempts with different credentials',
  ),

  /// API abuse (excessive mutations).
  apiAbuse(
    label: 'API Abuse',
    severity: AbuseSeverity.high,
    description: 'Excessive API mutation requests',
  ),

  /// Account enumeration attempt.
  accountEnumeration(
    label: 'Account Enumeration',
    severity: AbuseSeverity.medium,
    description: 'Pattern of attempts to discover valid accounts',
  );

  const AbuseTrigger({
    required this.label,
    required this.severity,
    required this.description,
  });

  /// Fixed, non-sensitive classification label.
  final String label;

  /// Severity level of the abuse pattern.
  final AbuseSeverity severity;

  /// Human-readable description of the trigger.
  final String description;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static AbuseTrigger fromWireName(String wire) {
    return AbuseTrigger.values.firstWhere(
      (t) => t.name == wire,
      orElse: () => throw FormatException('Unknown abuse trigger: $wire'),
    );
  }
}

/// Abuse severity levels (Task 11.3).
enum AbuseSeverity {
  /// Low severity — informational, no immediate action required.
  low('LOW', 'Low'),

  /// Medium severity — monitoring increased, possible throttling.
  medium('MEDIUM', 'Medium'),

  /// High severity — immediate rate limiting, cooldown enforced.
  high('HIGH', 'High'),

  /// Critical severity — temporary account suspension recommended.
  critical('CRITICAL', 'Critical');

  const AbuseSeverity(this.label, this.shortLabel);

  /// Fixed severity label.
  final String label;

  /// Short display label.
  final String shortLabel;

  /// Parse from a wire string; throws [FormatException] on unknown codes.
  static AbuseSeverity fromWireName(String wire) {
    return AbuseSeverity.values.firstWhere(
      (s) => s.name == wire,
      orElse: () => throw FormatException('Unknown abuse severity: $wire'),
    );
  }
}

/// An abuse detection event (Task 11.3).
///
/// Records when a specific abuse trigger was detected for auditing.
///
/// SECURITY CHECKPOINT (11.3): events carry ONLY the fixed trigger type,
/// severity label, and timestamp. No identity, no phone numbers, no
/// email addresses, no blind hashes.
class AbuseEvent {
  /// UUID v4 identifier for this event.
  final String eventId;

  /// The abuse trigger that was detected.
  final AbuseTrigger trigger;

  /// When the event was detected (UTC).
  final DateTime detectedAt;

  /// Number of occurrences that triggered this event.
  final int occurrenceCount;

  const AbuseEvent({
    required this.eventId,
    required this.trigger,
    required this.detectedAt,
    required this.occurrenceCount,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AbuseEvent &&
          runtimeType == other.runtimeType &&
          eventId == other.eventId;

  @override
  int get hashCode => eventId.hashCode;
}
