import 'dart:math';

/// Exponential backoff policy for sync queue retries (Task 3.3; jitter in
/// Task 5.2).
///
/// Retry delays follow the sequence 1s, 2s, 4s, 8s ... doubling per retry,
/// capped at a 5-minute maximum. [delayForRetry] is DETERMINISTIC (the base
/// schedule); [delayForRetryWithJitter] adds bounded randomization so a fleet
/// of reconnecting devices does not retry in lockstep (thundering-herd
/// avoidance). Pure domain logic — no timers or network, fully unit-testable.
class ExponentialBackoff {
  final Duration initialDelay;
  final Duration maxDelay;
  final double factor;

  const ExponentialBackoff({
    this.initialDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(minutes: 5),
    this.factor = 2,
  });

  /// The delay to wait before the [retryCount]-th retry.
  ///
  /// [retryCount] is 1-based: the 1st retry waits [initialDelay], the 2nd
  /// waits initial*factor, and so on. Values grow geometrically and are
  /// clamped at [maxDelay]. A [retryCount] <= 0 returns [initialDelay].
  Duration delayForRetry(int retryCount) {
    if (retryCount <= 1) {
      return initialDelay;
    }
    var delay = initialDelay;
    for (var i = 1; i < retryCount; i++) {
      delay = Duration(microseconds: (delay.inMicroseconds * factor).round());
      if (delay >= maxDelay) {
        return maxDelay;
      }
    }
    return delay;
  }

  /// The delay before the [retryCount]-th retry, with equal jitter (Task 5.2).
  ///
  /// Equal jitter picks uniformly from `[base/2, base)` where [base] is
  /// [delayForRetry]. Unlike full jitter, it guarantees a MINIMUM wait of
  /// half the base — so it is safe to use as a retry-eligibility GATE (an item
  /// is never retryable before `base/2` has elapsed) while still
  /// decorrelating concurrent retries across a fleet. The result is never
  /// negative and never exceeds [maxDelay] (the base is already capped).
  ///
  /// A [Random] may be injected for deterministic tests.
  Duration delayForRetryWithJitter(int retryCount, {Random? random}) {
    final base = delayForRetry(retryCount);
    final rng = random ?? Random();
    // Uniform over [0.5, 1.0) * base; a zero base (guard) yields zero.
    if (base == Duration.zero) {
      return Duration.zero;
    }
    final half = base.inMicroseconds / 2;
    final micros = (half + rng.nextDouble() * half).floor();
    return Duration(microseconds: micros);
  }
}
