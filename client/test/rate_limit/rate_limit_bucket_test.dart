import 'package:civic_commons/rate_limit/domain/rate_limit_bucket.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateLimitBucket', () {
    late RateLimitBucket bucket;
    late DateTime baseTime;

    setUp(() {
      baseTime = DateTime.utc(2026, 8, 19, 12, 0, 0);
      bucket = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 0,
        windowStart: baseTime,
      );
    });

    test('initial state has zero requests', () {
      expect(bucket.requestCount, 0);
      expect(bucket.isLimitReached, false);
      expect(bucket.cooldownActive, false);
      expect(bucket.remainingRequests, RateLimitPolicy.otpRequest.maxRequests);
    });

    test('withRequest increments count', () {
      final updated = bucket.withRequest(baseTime);
      expect(updated.requestCount, 1);
      expect(updated.cooldownActive, false);
    });

    test('withRequest activates cooldown when limit reached', () {
      var b = bucket;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        b = b.withRequest(baseTime);
      }
      expect(b.requestCount, RateLimitPolicy.otpRequest.maxRequests);
      expect(b.isLimitReached, true);
      expect(b.cooldownActive, true);
      expect(b.remainingRequests, 0);
    });

    test('withRequest resets window when window expired', () {
      var b = bucket;
      // Fill up the bucket
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        b = b.withRequest(baseTime);
      }
      expect(b.cooldownActive, true);

      // Move time past the window
      final expiredTime = baseTime.add(
        Duration(seconds: RateLimitPolicy.otpRequest.windowSeconds + 1),
      );
      final reset = b.withRequest(expiredTime);
      expect(reset.requestCount, 1);
      expect(reset.cooldownActive, false);
    });

    test('withReset clears cooldown', () {
      var b = bucket;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        b = b.withRequest(baseTime);
      }
      expect(b.cooldownActive, true);

      final reset = b.withReset(baseTime);
      expect(reset.requestCount, 0);
      expect(reset.cooldownActive, false);
      expect(reset.remainingRequests, RateLimitPolicy.otpRequest.maxRequests);
    });

    test('cooldownRemainingSeconds returns 0 when not in cooldown', () {
      expect(bucket.cooldownRemainingSeconds(baseTime), 0);
    });

    test('cooldownRemainingSeconds returns correct remaining', () {
      var b = bucket;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        b = b.withRequest(baseTime);
      }
      final remaining = b.cooldownRemainingSeconds(baseTime);
      expect(remaining, greaterThan(0));
      expect(remaining, lessThanOrEqualTo(RateLimitPolicy.otpRequest.cooldownSeconds));
    });

    test('equality based on policy and request count', () {
      final b1 = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 3,
        windowStart: baseTime,
      );
      final b2 = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 3,
        windowStart: baseTime.add(const Duration(hours: 1)),
      );
      expect(b1, equals(b2));

      final b3 = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 4,
        windowStart: baseTime,
      );
      expect(b1, isNot(equals(b3)));
    });

    test('isWindowExpired returns true when window elapsed', () {
      final expired = bucket.isWindowExpired(
        baseTime.add(Duration(seconds: RateLimitPolicy.otpRequest.windowSeconds)),
      );
      expect(expired, true);
    });

    test('isWindowExpired returns false within window', () {
      final notExpired = bucket.isWindowExpired(
        baseTime.add(const Duration(seconds: 1)),
      );
      expect(notExpired, false);
    });

    test('isCooldownExpired returns true when cooldown elapsed', () {
      var b = bucket;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        b = b.withRequest(baseTime);
      }
      expect(b.cooldownActive, true);

      final expired = b.isCooldownExpired(
        baseTime.add(Duration(seconds: RateLimitPolicy.otpRequest.cooldownSeconds + 1)),
      );
      expect(expired, true);
    });

    test('isCooldownExpired returns true when not in cooldown', () {
      expect(bucket.isCooldownExpired(baseTime), true);
    });
  });
}
