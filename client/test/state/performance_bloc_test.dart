import 'package:civic_commons/performance/data/in_memory_performance_repository.dart';
import 'package:civic_commons/performance/data/in_memory_startup_optimizer.dart';
import 'package:civic_commons/performance/domain/performance_metrics.dart';
import 'package:civic_commons/performance/domain/startup_optimizer.dart';
import 'package:civic_commons/state/data/local_performance_bloc.dart';
import 'package:civic_commons/state/domain/performance_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalPerformanceBloc - Task 12.1', () {
    late InMemoryPerformanceRepository repo;
    late InMemoryStartupOptimizer optimizer;
    late LocalPerformanceBloc bloc;

    setUp(() {
      repo = InMemoryPerformanceRepository();
      optimizer = InMemoryStartupOptimizer();
      bloc = LocalPerformanceBloc(
        repository: repo,
        optimizer: optimizer,
      );
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is idle with zero metrics', () {
      expect(bloc.current.phase, PerformancePhase.idle);
      expect(bloc.current.metrics, const PerformanceMetrics());
    });

    test('startMeasuring transitions to measuring then ready', () async {
      final states = <PerformanceState>[];
      bloc.state.listen(states.add);

      bloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states, hasLength(greaterThanOrEqualTo(2)));
      expect(states.first.phase, PerformancePhase.measuring);
      expect(states.last.phase, PerformancePhase.ready);
    });

    test('recordColdStart updates metrics', () async {
      bloc.recordColdStart(450);
      expect(bloc.current.metrics.coldStartMs, 450);
    });

    test('recordWarmStart updates metrics', () async {
      bloc.recordWarmStart(120);
      expect(bloc.current.metrics.warmStartMs, 120);
    });

    test('requestPillar registers and requests a pillar', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      bloc.requestPillar('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.requested, true);
      expect(bloc.current.deferredPillars, hasLength(1));
    });

    test('startPillarLoading transitions pillar to loading', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      bloc.startPillarLoading('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.state, DeferredPillarState.loading);
    });

    test('completePillarLoading transitions pillar to ready', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      bloc.startPillarLoading('vault');
      bloc.completePillarLoading('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.state, DeferredPillarState.ready);
    });

    test('refresh reloads metrics from repository', () async {
      await repo.recordColdStart(500);
      await bloc.refresh();
      expect(bloc.current.metrics.coldStartMs, 500);
    });

    test('repository failure emits error state', () async {
      final failingRepo = _FailingPerformanceRepository();
      final failingBloc = LocalPerformanceBloc(
        repository: failingRepo,
        optimizer: optimizer,
      );

      final states = <PerformanceState>[];
      failingBloc.state.listen(states.add);

      failingBloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states.last.phase, PerformancePhase.error);
      expect(states.last.errorMessage, isNotNull);

      failingBloc.close();
    });

    test('close prevents further updates', () {
      bloc.close();
      // These should not throw
      bloc.recordColdStart(100);
      bloc.requestPillar('vault');
      bloc.startPillarLoading('vault');
      bloc.completePillarLoading('vault');
    });

    test('state stream emits updates', () async {
      final states = <PerformanceState>[];
      final sub = bloc.state.listen(states.add);

      bloc.recordColdStart(300);
      await Future<void>.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(states.last.metrics.coldStartMs, 300);

      await sub.cancel();
    });
  });
}

class _FailingPerformanceRepository implements InMemoryPerformanceRepository {
  @override
  Future<PerformanceMetrics> getMetrics() async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordColdStart(int milliseconds) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordWarmStart(int milliseconds) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordMemoryUsage(int bytes) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> updatePeakMemory(int currentBytes) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordImageCacheUpdate({
    required int count,
    required int totalBytes,
  }) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordLazyLoadedCount(int count) async =>
      throw StateError('Simulated failure');

  @override
  Future<void> recordDeferredLoad() async =>
      throw StateError('Simulated failure');

  @override
  PerformanceMetrics get current => const PerformanceMetrics();
}
