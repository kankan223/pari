import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/rate_limit/domain/abuse_trigger.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_bucket.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryRateLimitRepository repo;

  setUp(() {
    repo = InMemoryRateLimitRepository();
  });

  group('getBucket', () {
    test('returns default bucket when none exists', () async {
      final bucket = await repo.getBucket(RateLimitPolicy.otpRequest);
      expect(bucket.policy, RateLimitPolicy.otpRequest);
      expect(bucket.requestCount, 0);
      expect(bucket.cooldownActive, false);
    });
  });

  group('recordRequest', () {
    test('increments request count', () async {
      final bucket = await repo.recordRequest(RateLimitPolicy.otpRequest);
      expect(bucket.requestCount, 1);
    });

    test('activates cooldown when limit reached', () async {
      RateLimitBucket? bucket;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        bucket = await repo.recordRequest(RateLimitPolicy.otpRequest);
      }
      expect(bucket!.isLimitReached, true);
      expect(bucket.cooldownActive, true);
    });

    test('tracks different policies independently', () async {
      await repo.recordRequest(RateLimitPolicy.otpRequest);
      await repo.recordRequest(RateLimitPolicy.otpRequest);
      await repo.recordRequest(RateLimitPolicy.loginAttempt);

      final otpBucket = await repo.getBucket(RateLimitPolicy.otpRequest);
      final loginBucket = await repo.getBucket(RateLimitPolicy.loginAttempt);

      expect(otpBucket.requestCount, 2);
      expect(loginBucket.requestCount, 1);
    });
  });

  group('getAbuseEvents', () {
    test('returns empty list initially', () async {
      final events = await repo.getAbuseEvents();
      expect(events, isEmpty);
    });

    test('returns all events when no since filter', () async {
      final now = DateTime.now().toUtc();
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: now,
        occurrenceCount: 5,
      ));
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-2',
        trigger: AbuseTrigger.rapidLoginFailures,
        detectedAt: now.add(const Duration(minutes: 1)),
        occurrenceCount: 10,
      ));

      final events = await repo.getAbuseEvents();
      expect(events.length, 2);
    });

    test('filters by since timestamp', () async {
      final now = DateTime.now().toUtc();
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: now,
        occurrenceCount: 5,
      ));
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-2',
        trigger: AbuseTrigger.rapidLoginFailures,
        detectedAt: now.add(const Duration(minutes: 5)),
        occurrenceCount: 10,
      ));

      final events = await repo.getAbuseEvents(
        since: now.add(const Duration(minutes: 2)),
      );
      expect(events.length, 1);
      expect(events.first.eventId, 'evt-2');
    });
  });

  group('recordAbuseEvent', () {
    test('stores events', () async {
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-1',
        trigger: AbuseTrigger.lockstepVoting,
        detectedAt: DateTime.now().toUtc(),
        occurrenceCount: 3,
      ));

      final count = await repo.getAbuseEventCount();
      expect(count, 1);
    });
  });

  group('getAbuseEventCount', () {
    test('returns 0 initially', () async {
      expect(await repo.getAbuseEventCount(), 0);
    });

    test('returns correct count after events', () async {
      final now = DateTime.now().toUtc();
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: now,
        occurrenceCount: 5,
      ));
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-2',
        trigger: AbuseTrigger.rapidLoginFailures,
        detectedAt: now,
        occurrenceCount: 10,
      ));

      expect(await repo.getAbuseEventCount(), 2);
    });
  });

  group('clear', () {
    test('resets all state', () async {
      await repo.recordRequest(RateLimitPolicy.otpRequest);
      await repo.recordAbuseEvent(AbuseEvent(
        eventId: 'evt-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: DateTime.now().toUtc(),
        occurrenceCount: 5,
      ));

      repo.clear();

      final bucket = await repo.getBucket(RateLimitPolicy.otpRequest);
      expect(bucket.requestCount, 0);
      expect(await repo.getAbuseEventCount(), 0);
    });
  });
}
