import 'package:civic_commons/rate_limit/domain/rate_limit_bucket.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:civic_commons/state/domain/rate_limit_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateLimitState', () {
    test('default state is idle with empty data', () {
      const state = RateLimitState();
      expect(state.phase, RateLimitPhase.idle);
      expect(state.buckets, isEmpty);
      expect(state.abuseEvents, isEmpty);
      expect(state.totalAbuseEvents, 0);
      expect(state.errorMessage, null);
    });

    test('bucketFor returns null for unknown policy', () {
      const state = RateLimitState();
      expect(state.bucketFor('unknown'), null);
    });

    test('bucketFor returns bucket for known policy', () {
      final bucket = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 3,
        windowStart: DateTime.now().toUtc(),
      );
      final state = RateLimitState(
        phase: RateLimitPhase.ready,
        buckets: {'otpRequest': bucket},
      );

      expect(state.bucketFor('otpRequest'), bucket);
    });

    test('anyCooldownActive is false when no buckets in cooldown', () {
      final bucket = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 1,
        windowStart: DateTime.now().toUtc(),
        cooldownActive: false,
      );
      final state = RateLimitState(
        phase: RateLimitPhase.ready,
        buckets: {'otpRequest': bucket},
      );

      expect(state.anyCooldownActive, false);
    });

    test('anyCooldownActive is true when any bucket in cooldown', () {
      final bucket = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 5,
        windowStart: DateTime.now().toUtc(),
        cooldownActive: true,
      );
      final state = RateLimitState(
        phase: RateLimitPhase.ready,
        buckets: {'otpRequest': bucket},
      );

      expect(state.anyCooldownActive, true);
    });

    test('error state carries error message', () {
      const state = RateLimitState(
        phase: RateLimitPhase.error,
        errorMessage: 'Unable to load rate limit data',
      );

      expect(state.phase, RateLimitPhase.error);
      expect(state.errorMessage, 'Unable to load rate limit data');
    });
  });
}
