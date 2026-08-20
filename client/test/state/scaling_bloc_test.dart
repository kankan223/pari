import 'package:civic_commons/scaling/data/in_memory_scaling_repository.dart';
import 'package:civic_commons/scaling/domain/load_test_scenario.dart';
import 'package:civic_commons/state/data/local_scaling_bloc.dart';
import 'package:civic_commons/state/domain/scaling_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LocalScalingBloc - Task 12.4', () {
    late InMemoryScalingRepository repo;
    late LocalScalingBloc bloc;

    setUp(() {
      repo = InMemoryScalingRepository();
      bloc = LocalScalingBloc(repository: repo);
    });

    tearDown(() {
      bloc.close();
    });

    test('initial state is idle with zero metrics', () {
      expect(bloc.current.phase, ScalingPhase.idle);
      expect(bloc.current.metrics.activeConnections, 0);
    });

    test('startMeasuring transitions to ready', () async {
      final states = <ScalingState>[];
      bloc.state.listen(states.add);

      bloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(states.last.phase, ScalingPhase.ready);
    });

    test('runLoadTest transitions through running to ready', () async {
      final states = <ScalingState>[];
      final sub = bloc.state.listen(states.add);

      const scenario = LoadTestScenario(
        id: 'test',
        name: 'Test',
        concurrentUsers: 100,
      );
      await bloc.runLoadTest(scenario);
      await Future<void>.delayed(Duration.zero);

      expect(states.any((s) => s.phase == ScalingPhase.running), isTrue);
      expect(states.last.phase, ScalingPhase.ready);
      expect(states.last.metrics.activeConnections, 100);
      await sub.cancel();
    });

    test('recordRequest updates metrics', () {
      bloc.recordRequest(success: true, latencyMs: 50, shardId: 'shard_11');
      expect(bloc.current.metrics.totalRequests, 1);
      expect(bloc.current.metrics.successfulRequests, 1);
    });

    test('recordConnection updates active connections', () {
      bloc.recordConnection(opened: true);
      bloc.recordConnection(opened: true);
      expect(bloc.current.metrics.activeConnections, 2);
      expect(bloc.current.metrics.peakConnections, 2);
    });

    test('refresh reloads metrics', () async {
      await repo.recordRequest(success: true, latencyMs: 50, shardId: 's');
      await bloc.refresh();
      expect(bloc.current.metrics.totalRequests, 1);
    });

    test('repository failure emits error state', () async {
      final failingRepo = _FailingScalingRepository();
      final failingBloc = LocalScalingBloc(repository: failingRepo);

      final states = <ScalingState>[];
      failingBloc.state.listen(states.add);

      failingBloc.startMeasuring();
      await Future<void>.delayed(Duration.zero);

      expect(states.last.phase, ScalingPhase.error);
      expect(states.last.errorMessage, isNotNull);

      failingBloc.close();
    });

    test('close prevents further updates', () {
      bloc.close();
      // These should not throw
      bloc.recordRequest(success: true, latencyMs: 50, shardId: 's');
      bloc.recordConnection(opened: true);
    });

    test('state stream emits updates', () async {
      final states = <ScalingState>[];
      final sub = bloc.state.listen(states.add);

      bloc.recordRequest(success: true, latencyMs: 50, shardId: 's');
      await Future<void>.delayed(Duration.zero);

      expect(states, isNotEmpty);
      expect(states.last.metrics.totalRequests, 1);

      await sub.cancel();
    });
  });
}

class _FailingScalingRepository implements InMemoryScalingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('Simulated failure');
}
