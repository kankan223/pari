import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RateLimitPolicy', () {
    test('has 8 fixed policies', () {
      expect(RateLimitPolicy.values.length, 8);
    });

    test('fromWireName returns correct policy', () {
      expect(RateLimitPolicy.fromWireName('otpRequest'),
          RateLimitPolicy.otpRequest);
      expect(RateLimitPolicy.fromWireName('loginAttempt'),
          RateLimitPolicy.loginAttempt);
      expect(RateLimitPolicy.fromWireName('usernameClaim'),
          RateLimitPolicy.usernameClaim);
      expect(RateLimitPolicy.fromWireName('connectionRequest'),
          RateLimitPolicy.connectionRequest);
      expect(RateLimitPolicy.fromWireName('postCreation'),
          RateLimitPolicy.postCreation);
      expect(RateLimitPolicy.fromWireName('voteAction'),
          RateLimitPolicy.voteAction);
      expect(RateLimitPolicy.fromWireName('apiMutation'),
          RateLimitPolicy.apiMutation);
      expect(RateLimitPolicy.fromWireName('generalAction'),
          RateLimitPolicy.generalAction);
    });

    test('fromWireName throws on unknown', () {
      expect(
        () => RateLimitPolicy.fromWireName('unknown'),
        throwsFormatException,
      );
    });

    test('fromWireName throws on empty string', () {
      expect(
        () => RateLimitPolicy.fromWireName(''),
        throwsFormatException,
      );
    });

    test('labels are non-empty', () {
      for (final policy in RateLimitPolicy.values) {
        expect(policy.label, isNotEmpty);
        expect(policy.maxRequests, greaterThan(0));
        expect(policy.windowSeconds, greaterThan(0));
        expect(policy.cooldownSeconds, greaterThan(0));
      }
    });

    test('all policies have positive max requests', () {
      for (final policy in RateLimitPolicy.values) {
        expect(policy.maxRequests, greaterThan(0),
            reason: '${policy.name} should have positive maxRequests');
      }
    });

    test('all policies have positive window seconds', () {
      for (final policy in RateLimitPolicy.values) {
        expect(policy.windowSeconds, greaterThan(0),
            reason: '${policy.name} should have positive windowSeconds');
      }
    });
  });
}
