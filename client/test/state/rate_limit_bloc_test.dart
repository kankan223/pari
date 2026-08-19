import 'package:civic_commons/rate_limit/data/in_memory_rate_limit_repository.dart';
import 'package:civic_commons/rate_limit/domain/rate_limit_policy.dart';
import 'package:civic_commons/state/data/local_rate_limit_bloc.dart';
import 'package:civic_commons/state/domain/rate_limit_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryRateLimitRepository repo;
  late LocalRateLimitBloc bloc;

  setUp(() {
    repo = InMemoryRateLimitRepository();
    bloc = LocalRateLimitBloc(repository: repo);
  });

  tearDown(() async {
    await bloc.close();
  });

  group('initial state', () {
    test('starts in idle phase', () {
      expect(bloc.current.phase, RateLimitPhase.idle);
    });
  });

  group('refresh', () {
    test('transitions to ready with all policies', () async {
      await bloc.refresh();

      expect(bloc.current.phase, RateLimitPhase.ready);
      expect(bloc.current.buckets.length, RateLimitPolicy.values.length);
    });

    test('loads existing bucket data', () async {
      await repo.recordRequest(RateLimitPolicy.otpRequest);
      await repo.recordRequest(RateLimitPolicy.otpRequest);

      await bloc.refresh();

      final bucket = bloc.current.bucketFor('otpRequest');
      expect(bucket, isNotNull);
      expect(bucket!.requestCount, 2);
    });
  });

  group('recordRequest', () {
    test('increments request count and returns false when not at limit',
        () async {
      await bloc.refresh();

      final limitReached = await bloc.recordRequest(RateLimitPolicy.otpRequest);

      expect(limitReached, false);
      final bucket = bloc.current.bucketFor('otpRequest');
      expect(bucket!.requestCount, 1);
    });

    test('returns true when limit is reached', () async {
      await bloc.refresh();

      bool limitReached = false;
      for (var i = 0; i < RateLimitPolicy.otpRequest.maxRequests; i++) {
        limitReached = await bloc.recordRequest(RateLimitPolicy.otpRequest);
      }

      expect(limitReached, true);
      final bucket = bloc.current.bucketFor('otpRequest');
      expect(bucket!.cooldownActive, true);
    });
  });

  group('stream', () {
    test('emits states on refresh', () async {
      final states = <RateLimitState>[];
      bloc.state.listen(states.add);

      await bloc.refresh();

      // Wait for broadcast stream delivery
      await Future<void>.delayed(Duration.zero);

      expect(states.length, greaterThanOrEqualTo(2));
      expect(states.first.phase, RateLimitPhase.loading);
      expect(states.last.phase, RateLimitPhase.ready);
    });
  });

  group('error handling', () {
    test('repository failure emits error state', () async {
      final badRepo = _FailingRepository();
      final badBloc = LocalRateLimitBloc(repository: badRepo);

      await badBloc.refresh();

      expect(badBloc.current.phase, RateLimitPhase.error);
      expect(badBloc.current.errorMessage, isNotNull);

      await badBloc.close();
    });
  });
}

class _FailingRepository implements InMemoryRateLimitRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) {
    throw StateError('Simulated failure');
  }
}
