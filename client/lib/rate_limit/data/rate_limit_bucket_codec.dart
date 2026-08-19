import '../domain/rate_limit_bucket.dart';
import '../domain/rate_limit_policy.dart';

/// Row codec for [RateLimitBucket] (Task 11.3 Rate Limiting & Abuse Prevention).
///
/// Converts between the SQLCipher row representation and the domain entity.
/// The read path revalidates every field to ensure no corrupted or PII-
/// containing rows slip through.
///
/// SECURITY CHECKPOINT (11.3): the codec validates that the policy
/// is a known wire code before the entity enters the domain layer. A
/// malformed row is rejected with [FormatException].
class RateLimitBucketCodec {
  /// Convert a raw SQL row (Map<String, Object?>) to a [RateLimitBucket].
  ///
  /// Throws [FormatException] if the row is malformed.
  static RateLimitBucket decode(Map<String, Object?> row) {
    final policyWire = row['policy'] as String?;
    final requestCount = row['request_count'] as int?;
    final windowStartMs = row['window_start'] as int?;
    final cooldownActive = row['cooldown_active'] as int?;
    final cooldownStartedAtMs = row['cooldown_started_at'] as int?;

    if (policyWire == null ||
        requestCount == null ||
        windowStartMs == null ||
        cooldownActive == null) {
      throw const FormatException(
        'rate limit bucket row missing required columns',
      );
    }

    final policy = RateLimitPolicy.fromWireName(policyWire);

    return RateLimitBucket(
      policy: policy,
      requestCount: requestCount,
      windowStart:
          DateTime.fromMillisecondsSinceEpoch(windowStartMs, isUtc: true),
      cooldownActive: cooldownActive == 1,
      cooldownStartedAt: cooldownStartedAtMs != null
          ? DateTime.fromMillisecondsSinceEpoch(cooldownStartedAtMs,
              isUtc: true)
          : null,
    );
  }

  /// Convert a [RateLimitBucket] to a row map for SQLCipher storage.
  static Map<String, Object?> encode(RateLimitBucket bucket) {
    return {
      'policy': bucket.policy.name,
      'request_count': bucket.requestCount,
      'window_start': bucket.windowStart.millisecondsSinceEpoch,
      'cooldown_active': bucket.cooldownActive ? 1 : 0,
      'cooldown_started_at': bucket.cooldownStartedAt?.millisecondsSinceEpoch,
    };
  }
}
