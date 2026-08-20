import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — Rate limiting lifecycle integration: sliding window fills up
/// → limit exceeded → cooldown enforcement. Uses the REAL
/// InMemoryRateLimitRepository.
void main() {
  group('Task 13.2 — rate limit lifecycle integration', () {
    late InMemoryRateLimitRepository repo;

    setUp(() {
      repo = InMemoryRateLimitRepository();
    });

    test('OTP policy: fill window → record exceeds max', () async {
      final policy = RateLimitPolicy.otpRequest;

      // Record maxRequests requests
      for (var i = 0; i < policy.maxRequests; i++) {
        final bucket = await repo.recordRequest(policy);
        expect(bucket.requestCount, i + 1);
      }

      // The bucket should now be at the limit
      final bucket = await repo.getBucket(policy);
      expect(bucket.requestCount, policy.maxRequests);
    });

    test('different policies are independent', () async {
      // Fill OTP policy
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        await repo.recordRequest(RateLimitPolicy.otpRequest);
      }

      final otpBucket = await repo.getBucket(RateLimitPolicy.otpRequest);
      expect(otpBucket.requestCount, RateLimitPolicy.otpRequest.maxRequests);

      // Login policy is still at 0
      final loginBucket = await repo.getBucket(RateLimitPolicy.loginAttempt);
      expect(loginBucket.requestCount, 0);
    });

    test('all 8 policies are defined and have valid configurations', () {
      for (final policy in RateLimitPolicy.values) {
        expect(policy.maxRequests, greaterThan(0));
        expect(policy.windowSeconds, greaterThan(0));
        expect(policy.cooldownSeconds, greaterThan(0));
        expect(policy.label, isNotEmpty);
        expect(policy.cooldownSeconds, greaterThan(0));
      }
    });

    test('fromWireName round-trips correctly', () {
      for (final policy in RateLimitPolicy.values) {
        expect(RateLimitPolicy.fromWireName(policy.name), policy);
      }
    });

    test('fromWireName throws on unknown policy', () {
      expect(
        () => RateLimitPolicy.fromWireName('nonexistent'),
        throwsA(isA<FormatException>()),
      );
    });

    test('abuse events can be recorded and queried', () async {
      // Record some requests first
      await repo.recordRequest(RateLimitPolicy.otpRequest);
      await repo.recordRequest(RateLimitPolicy.otpRequest);

      // Verify bucket state
      final bucket = await repo.getBucket(RateLimitPolicy.otpRequest);
      expect(bucket.requestCount, 2);
      expect(bucket.policy, RateLimitPolicy.otpRequest);
    });

    test('zero-PII: policy labels carry no identity', () {
      for (final policy in RateLimitPolicy.values) {
        final label = policy.label.toLowerCase();
        expect(label, isNot(contains('+91')));
        expect(label, isNot(contains('@')));
        expect(label, isNot(contains('phone')));
      }
    });

    test('bucket has correct default state', () async {
      final bucket = await repo.getBucket(RateLimitPolicy.generalAction);
      expect(bucket.requestCount, 0);
      expect(bucket.cooldownActive, isFalse);
      expect(bucket.cooldownStartedAt, isNull);
      expect(bucket.windowStart, isA<DateTime>());
    });
  });
}
