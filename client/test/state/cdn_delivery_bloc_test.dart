import 'package:civic_commons/cdn/data/in_memory_cdn_repository.dart';
import 'package:civic_commons/state/data/local_cdn_delivery_bloc.dart';
import 'package:civic_commons/state/domain/cdn_delivery_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalCdnDeliveryBloc - Task 12.3', () {
    late InMemoryCdnRepository repo;
    late LocalCdnDeliveryBloc bloc;

    setUp(() {
      repo = InMemoryCdnRepository();
      bloc = LocalCdnDeliveryBloc(repository: repo);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is idle with zero metrics', () {
      expect(bloc.current.phase, CdnDeliveryPhase.idle);
      expect(bloc.current.metrics.ttfbMs, 0);
    });

    test('startMeasuring transitions to measuring then ready', () async {
      final states = <CdnDeliveryState>[];
      bloc.state.listen(states.add);

      bloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states, hasLength(greaterThanOrEqualTo(2)));
      expect(states.first.phase, CdnDeliveryPhase.measuring);
      expect(states.last.phase, CdnDeliveryPhase.ready);
    });

    test('recordCacheHit updates metrics', () async {
      bloc.recordCacheHit(1024);
      expect(bloc.current.metrics.bytesFromCache, 1024);
      expect(bloc.current.metrics.cacheHits, 1);
    });

    test('recordDownload updates metrics', () async {
      bloc.recordDownload(
        bytesDownloaded: 2048,
        ttfbMs: 50,
        downloadTimeMs: 200,
      );
      expect(bloc.current.metrics.ttfbMs, 50);
      expect(bloc.current.metrics.bytesDownloaded, 2048);
    });

    test('recordFailure increments failed downloads', () async {
      bloc.recordFailure();
      expect(bloc.current.metrics.failedDownloads, 1);
    });

    test('refresh reloads metrics from repository', () async {
      await repo.recordCacheHit(500);
      await bloc.refresh();
      expect(bloc.current.metrics.bytesFromCache, 500);
    });

    test('repository failure emits error state', () async {
      final failingRepo = _FailingCdnRepository();
      final failingBloc = LocalCdnDeliveryBloc(repository: failingRepo);

      final states = <CdnDeliveryState>[];
      failingBloc.state.listen(states.add);

      failingBloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states.last.phase, CdnDeliveryPhase.error);
      expect(states.last.errorMessage, isNotNull);

      failingBloc.close();
    });

    test('close prevents further updates', () {
      bloc.close();
      // These should not throw
      bloc.recordCacheHit(100);
      bloc.recordDownload(bytesDownloaded: 100, ttfbMs: 10, downloadTimeMs: 50);
      bloc.recordFailure();
    });

    test('state stream emits updates', () async {
      final states = <CdnDeliveryState>[];
      final sub = bloc.state.listen(states.add);

      bloc.recordCacheHit(256);
      await Future<void>.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(states.last.metrics.bytesFromCache, 256);

      await sub.cancel();
    });
  });
}

class _FailingCdnRepository implements InMemoryCdnRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Simulated failure');
}
