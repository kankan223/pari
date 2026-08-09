import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/domain/exponential_backoff.dart';

/// VERIFY (Task 3.3): exponential backoff calculation — 1s, 2s, 4s ...
/// capped at the 5-minute maximum. VERIFY (Task 5.2): jittered variant.
void main() {
  const backoff = ExponentialBackoff();

  group('ExponentialBackoff - delay calculation', () {
    test('first retry waits the initial delay (1s)', () {
      expect(backoff.delayForRetry(1), const Duration(seconds: 1));
      // retryCount <= 0 is clamped to the initial delay.
      expect(backoff.delayForRetry(0), const Duration(seconds: 1));
    });

    test('delays double each retry: 1s, 2s, 4s, 8s', () {
      expect(backoff.delayForRetry(1), const Duration(seconds: 1));
      expect(backoff.delayForRetry(2), const Duration(seconds: 2));
      expect(backoff.delayForRetry(3), const Duration(seconds: 4));
      expect(backoff.delayForRetry(4), const Duration(seconds: 8));
      expect(backoff.delayForRetry(5), const Duration(seconds: 16));
      expect(backoff.delayForRetry(6), const Duration(seconds: 32));
      expect(backoff.delayForRetry(7), const Duration(seconds: 64));
      expect(backoff.delayForRetry(8), const Duration(seconds: 128));
      expect(backoff.delayForRetry(9), const Duration(seconds: 256));
    });

    test('delay never exceeds the 5-minute maximum', () {
      // 2^9 = 512s > 300s → clamped at 5 minutes.
      expect(backoff.delayForRetry(10), const Duration(minutes: 5));
      expect(backoff.delayForRetry(11), const Duration(minutes: 5));
      expect(backoff.delayForRetry(20), const Duration(minutes: 5));
      expect(backoff.delayForRetry(100), const Duration(minutes: 5));
    });

    test('delay is monotonically non-decreasing', () {
      var previous = Duration.zero;
      for (var retry = 1; retry <= 20; retry++) {
        final delay = backoff.delayForRetry(retry);
        expect(delay >= previous, isTrue,
            reason: 'delay($retry)=$delay must not shrink');
        previous = delay;
      }
    });

    test('custom initial/max parameters are respected', () {
      const custom = ExponentialBackoff(
        initialDelay: Duration(milliseconds: 500),
        maxDelay: Duration(seconds: 4),
      );
      expect(custom.delayForRetry(1), const Duration(milliseconds: 500));
      expect(custom.delayForRetry(2), const Duration(seconds: 1));
      expect(custom.delayForRetry(4), const Duration(seconds: 4));
      // 8s would be next but is capped at the 4s maximum.
      expect(custom.delayForRetry(5), const Duration(seconds: 4));
    });
  });

  group('ExponentialBackoff - jittered delays (Task 5.2)', () {
    test('jittered delay stays within [base/2, base) (equal jitter)', () {
      final rng = Random(7);
      for (var retry = 1; retry <= 12; retry++) {
        final base = backoff.delayForRetry(retry);
        for (var sample = 0; sample < 50; sample++) {
          final jittered = backoff.delayForRetryWithJitter(retry, random: rng);
          // Equal jitter: never below half the base (retry-gating minimum),
          // never reaching the base, never above the 5-minute cap.
          expect(jittered >= Duration(microseconds: base.inMicroseconds ~/ 2),
              isTrue,
              reason: 'jittered delay $jittered must be >= base/2 ($base)');
          expect(jittered < base, isTrue,
              reason: 'jittered delay $jittered must be < base $base');
          expect(jittered <= backoff.maxDelay, isTrue,
              reason: 'jittered delay must respect the 5-minute cap');
        }
      }
    });

    test('jitter decorrelates concurrent retries (not lockstep)', () {
      // With a seeded RNG the values still vary per retry-count; across a
      // fleet, equal jitter spreads retries over [base/2, base).
      final rng = Random(1234);
      final seen = <Duration>{};
      for (var i = 0; i < 200; i++) {
        seen.add(backoff.delayForRetryWithJitter(3, random: rng));
      }
      // The 3rd retry base is 4s; jitter over [2s,4s) should produce a
      // spread of distinct values, not a single deterministic delay.
      expect(seen.length, greaterThan(1),
          reason: 'jitter must produce varied delays');
    });

    test('seeded jitter is deterministic for tests', () {
      final a = backoff.delayForRetryWithJitter(4, random: Random(99));
      final b = backoff.delayForRetryWithJitter(4, random: Random(99));
      expect(a, b);
    });

    test('base deterministic schedule is unchanged by the jitter method', () {
      // delayForRetry stays exact — the jittered variant is a separate path.
      expect(backoff.delayForRetry(5), const Duration(seconds: 16));
    });
  });
}
