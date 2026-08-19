import '../../rate_limit/domain/abuse_trigger.dart';
import '../../rate_limit/domain/rate_limit_bucket.dart';

/// Rate limit phases (Task 11.3).
enum RateLimitPhase {
  /// Not started.
  idle,

  /// Loading rate limit data.
  loading,

  /// Rate limit data is ready for display.
  ready,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Immutable state projection for the Rate Limiting & Abuse Prevention
/// system (Task 11.3).
///
/// Carries the current buckets, abuse events, and summary counts.
///
/// SECURITY CHECKPOINT (11.3): the state carries only fixed policy labels,
/// trigger labels, severity labels, and integer counts — no phone numbers,
/// no blind hashes, no identity fields.
class RateLimitState {
  final RateLimitPhase phase;
  final Map<String, RateLimitBucket> buckets;
  final List<AbuseEvent> abuseEvents;
  final int totalAbuseEvents;
  final String? errorMessage;

  const RateLimitState({
    this.phase = RateLimitPhase.idle,
    this.buckets = const {},
    this.abuseEvents = const [],
    this.totalAbuseEvents = 0,
    this.errorMessage,
  });

  /// Returns the bucket for a specific policy name, or null.
  RateLimitBucket? bucketFor(String policyName) => buckets[policyName];

  /// Whether any policy is currently in cooldown.
  bool get anyCooldownActive => buckets.values.any((b) => b.cooldownActive);
}
