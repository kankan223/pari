import '../domain/abuse_trigger.dart';
import '../domain/rate_limit_bucket.dart';
import '../domain/rate_limit_policy.dart';
import '../domain/rate_limit_repository.dart';

/// In-memory implementation of [RateLimitRepository] (Task 11.3).
///
/// Used in the testing harness and unit tests. Production persistence
/// backs onto the SQLCipher-encrypted database.
///
/// SECURITY CHECKPOINT (11.3): stores only [RateLimitBucket] and
/// [AbuseEvent] objects carrying fixed policy/trigger labels — no
/// identity, no PII, no tokens.
class InMemoryRateLimitRepository implements RateLimitRepository {
  final Map<String, RateLimitBucket> _buckets = {};
  final List<AbuseEvent> _abuseEvents = [];

  @override
  Future<RateLimitBucket> getBucket(RateLimitPolicy policy) async {
    return _buckets[policy.name] ??
        RateLimitBucket(
          policy: policy,
          requestCount: 0,
          windowStart: DateTime.now().toUtc(),
        );
  }

  @override
  Future<RateLimitBucket> recordRequest(RateLimitPolicy policy) async {
    final now = DateTime.now().toUtc();
    final current = _buckets[policy.name] ??
        RateLimitBucket(
          policy: policy,
          requestCount: 0,
          windowStart: now,
        );

    final updated = current.withRequest(now);
    _buckets[policy.name] = updated;
    return updated;
  }

  @override
  Future<List<AbuseEvent>> getAbuseEvents({DateTime? since}) async {
    if (since == null) {
      return List<AbuseEvent>.unmodifiable(_abuseEvents);
    }
    return List<AbuseEvent>.unmodifiable(
      _abuseEvents.where((e) => e.detectedAt.isAfter(since)),
    );
  }

  @override
  Future<void> recordAbuseEvent(AbuseEvent event) async {
    _abuseEvents.add(event);
  }

  @override
  Future<int> getAbuseEventCount() async => _abuseEvents.length;

  /// Clears all buckets and abuse events (for testing).
  void clear() {
    _buckets.clear();
    _abuseEvents.clear();
  }
}
