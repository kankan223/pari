import 'abuse_trigger.dart';
import 'rate_limit_bucket.dart';
import 'rate_limit_policy.dart';

/// Repository port for the Rate Limiting & Abuse Prevention system
/// (Task 11.3).
///
/// All operations are local-first and offline-safe. The repository tracks
/// request rates per policy and detects abuse patterns.
///
/// SECURITY CHECKPOINT (11.3): the repository carries only
/// [RateLimitBucket] and [AbuseEvent] objects with fixed policy/trigger
/// labels — no identity, no PII, no tokens.
abstract class RateLimitRepository {
  /// Returns the current bucket state for a given [policy].
  Future<RateLimitBucket> getBucket(RateLimitPolicy policy);

  /// Records a request for the given [policy] and returns the updated bucket.
  Future<RateLimitBucket> recordRequest(RateLimitPolicy policy);

  /// Returns all abuse events detected since [since].
  Future<List<AbuseEvent>> getAbuseEvents({DateTime? since});

  /// Records an abuse event.
  Future<void> recordAbuseEvent(AbuseEvent event);

  /// Returns the total number of abuse events.
  Future<int> getAbuseEventCount();
}
