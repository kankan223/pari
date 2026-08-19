import 'rate_limit_policy.dart';

/// A sliding-window rate limit bucket (Task 11.3).
///
/// Tracks the request count, window start time, and cooldown status for
/// a specific policy. Buckets are keyed by policy name — the repository
/// manages per-action tracking.
///
/// SECURITY CHECKPOINT (11.3): buckets carry ONLY the fixed policy name,
/// request count, and timestamps. No identity, no phone numbers, no
/// email addresses, no blind hashes.
class RateLimitBucket {
  /// The policy this bucket enforces.
  final RateLimitPolicy policy;

  /// Number of requests recorded in the current window.
  final int requestCount;

  /// Start of the current sliding window (UTC).
  final DateTime windowStart;

  /// Whether the cooldown is currently active (limit exceeded).
  final bool cooldownActive;

  /// When the cooldown started (null if not in cooldown).
  final DateTime? cooldownStartedAt;

  const RateLimitBucket({
    required this.policy,
    this.requestCount = 0,
    required this.windowStart,
    this.cooldownActive = false,
    this.cooldownStartedAt,
  });

  /// Whether the request count has reached or exceeded the policy limit.
  bool get isLimitReached => requestCount >= policy.maxRequests;

  /// Whether the current window has expired (needs a fresh window).
  bool isWindowExpired(DateTime now) {
    return now.difference(windowStart).inSeconds >= policy.windowSeconds;
  }

  /// Whether the cooldown period has elapsed.
  bool isCooldownExpired(DateTime now) {
    if (!cooldownActive || cooldownStartedAt == null) return true;
    return now.difference(cooldownStartedAt!).inSeconds >=
        policy.cooldownSeconds;
  }

  /// Returns a copy with the request count incremented.
  RateLimitBucket withRequest(DateTime now) {
    // If window expired or cooldown expired (and was active), start fresh.
    if (isWindowExpired(now) || (cooldownActive && isCooldownExpired(now))) {
      return RateLimitBucket(
        policy: policy,
        requestCount: 1,
        windowStart: now,
        cooldownActive: false,
        cooldownStartedAt: null,
      );
    }

    final newCount = requestCount + 1;
    final limitReached = newCount >= policy.maxRequests;

    return RateLimitBucket(
      policy: policy,
      requestCount: newCount,
      windowStart: windowStart,
      cooldownActive: limitReached,
      cooldownStartedAt: limitReached ? now : cooldownStartedAt,
    );
  }

  /// Returns a copy with the bucket reset (e.g., after cooldown expires).
  RateLimitBucket withReset(DateTime now) {
    return RateLimitBucket(
      policy: policy,
      requestCount: 0,
      windowStart: now,
      cooldownActive: false,
      cooldownStartedAt: null,
    );
  }

  /// How many requests remain in the current window.
  int get remainingRequests {
    if (cooldownActive) return 0;
    return (policy.maxRequests - requestCount).clamp(0, policy.maxRequests);
  }

  /// Seconds remaining in the cooldown period (0 if not in cooldown).
  int cooldownRemainingSeconds(DateTime now) {
    if (!cooldownActive || cooldownStartedAt == null) return 0;
    final elapsed = now.difference(cooldownStartedAt!).inSeconds;
    return (policy.cooldownSeconds - elapsed).clamp(0, policy.cooldownSeconds);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RateLimitBucket &&
          runtimeType == other.runtimeType &&
          policy == other.policy &&
          requestCount == other.requestCount;

  @override
  int get hashCode => policy.hashCode ^ requestCount.hashCode;
}
