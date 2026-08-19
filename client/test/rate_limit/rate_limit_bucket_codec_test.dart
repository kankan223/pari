import 'package:civic_commons/rate_limit/data/rate_limit_bucket_codec.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_bucket.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateLimitBucketCodec', () {
    final baseTime = DateTime.utc(2026, 8, 19, 12, 0, 0);

    test('encode produces correct row', () {
      final bucket = RateLimitBucket(
        policy: RateLimitPolicy.otpRequest,
        requestCount: 3,
        windowStart: baseTime,
        cooldownActive: true,
        cooldownStartedAt: baseTime,
      );

      final row = RateLimitBucketCodec.encode(bucket);

      expect(row['policy'], 'otpRequest');
      expect(row['request_count'], 3);
      expect(row['window_start'], baseTime.millisecondsSinceEpoch);
      expect(row['cooldown_active'], 1);
      expect(row['cooldown_started_at'], baseTime.millisecondsSinceEpoch);
    });

    test('decode round-trip preserves data', () {
      final bucket = RateLimitBucket(
        policy: RateLimitPolicy.loginAttempt,
        requestCount: 7,
        windowStart: baseTime,
        cooldownActive: false,
        cooldownStartedAt: null,
      );

      final row = RateLimitBucketCodec.encode(bucket);
      final decoded = RateLimitBucketCodec.decode(row);

      expect(decoded.policy, RateLimitPolicy.loginAttempt);
      expect(decoded.requestCount, 7);
      expect(decoded.windowStart, baseTime);
      expect(decoded.cooldownActive, false);
      expect(decoded.cooldownStartedAt, null);
    });

    test('decode with cooldown active', () {
      final row = {
        'policy': 'apiMutation',
        'request_count': 30,
        'window_start': baseTime.millisecondsSinceEpoch,
        'cooldown_active': 1,
        'cooldown_started_at': baseTime.millisecondsSinceEpoch,
      };

      final decoded = RateLimitBucketCodec.decode(row);

      expect(decoded.policy, RateLimitPolicy.apiMutation);
      expect(decoded.requestCount, 30);
      expect(decoded.cooldownActive, true);
      expect(decoded.cooldownStartedAt, baseTime);
    });

    test('decode throws FormatException for missing columns', () {
      expect(
        () => RateLimitBucketCodec.decode({}),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for unknown policy', () {
      expect(
        () => RateLimitBucketCodec.decode({
          'policy': 'unknownPolicy',
          'request_count': 1,
          'window_start': baseTime.millisecondsSinceEpoch,
          'cooldown_active': 0,
        }),
        throwsFormatException,
      );
    });

    test('decode handles null cooldown_started_at', () {
      final row = {
        'policy': 'generalAction',
        'request_count': 10,
        'window_start': baseTime.millisecondsSinceEpoch,
        'cooldown_active': 0,
        'cooldown_started_at': null,
      };

      final decoded = RateLimitBucketCodec.decode(row);

      expect(decoded.cooldownStartedAt, null);
    });

    test('all policy types round-trip', () {
      for (final policy in RateLimitPolicy.values) {
        final bucket = RateLimitBucket(
          policy: policy,
          requestCount: 1,
          windowStart: baseTime,
        );

        final row = RateLimitBucketCodec.encode(bucket);
        final decoded = RateLimitBucketCodec.decode(row);

        expect(decoded.policy, policy);
        expect(decoded.requestCount, 1);
      }
    });
  });
}
