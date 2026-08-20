import 'package:civic_commons/performance/domain/performance_metrics.dart';
import 'package:civic_commons/performance/domain/startup_optimizer.dart';
import 'package:civic_commons/state/domain/performance_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerformanceState - Task 12.1', () {
    test('default state has idle phase and zero metrics', () {
      const state = PerformanceState();
      expect(state.phase, PerformancePhase.idle);
      expect(state.metrics, const PerformanceMetrics());
      expect(state.deferredPillars, isEmpty);
      expect(state.errorMessage, isNull);
    });

    test('copyWith creates new instance with updated values', () {
      const original = PerformanceState();
      final updated = original.copyWith(
        phase: PerformancePhase.ready,
        metrics: const PerformanceMetrics(coldStartMs: 450),
      );
      expect(updated.phase, PerformancePhase.ready);
      expect(updated.metrics.coldStartMs, 450);
      expect(original.phase, PerformancePhase.idle);
    });

    test('coldStartTargetMet delegates to metrics', () {
      const fast = PerformanceState(
        metrics: PerformanceMetrics(coldStartMs: 450),
      );
      const slow = PerformanceState(
        metrics: PerformanceMetrics(coldStartMs: 800),
      );
      expect(fast.coldStartTargetMet, true);
      expect(slow.coldStartTargetMet, false);
    });

    test('readyPillarCount counts ready pillars', () {
      const state = PerformanceState(
        deferredPillars: [
          DeferredPillar(
            pillarId: 'a',
            displayName: 'A',
            state: DeferredPillarState.ready,
          ),
          DeferredPillar(
            pillarId: 'b',
            displayName: 'B',
            state: DeferredPillarState.loading,
          ),
          DeferredPillar(
            pillarId: 'c',
            displayName: 'C',
            state: DeferredPillarState.ready,
          ),
        ],
      );
      expect(state.readyPillarCount, 2);
    });

    test('loadingPillarCount counts loading pillars', () {
      const state = PerformanceState(
        deferredPillars: [
          DeferredPillar(
            pillarId: 'a',
            displayName: 'A',
            state: DeferredPillarState.loading,
          ),
          DeferredPillar(
            pillarId: 'b',
            displayName: 'B',
            state: DeferredPillarState.ready,
          ),
        ],
      );
      expect(state.loadingPillarCount, 1);
    });

    test('equality compares phase, metrics, and errorMessage', () {
      const a = PerformanceState(
        phase: PerformancePhase.ready,
        metrics: PerformanceMetrics(coldStartMs: 100),
      );
      const b = PerformanceState(
        phase: PerformancePhase.ready,
        metrics: PerformanceMetrics(coldStartMs: 100),
      );
      const c = PerformanceState(
        phase: PerformancePhase.error,
        metrics: PerformanceMetrics(coldStartMs: 100),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('errorMessage is included in copyWith', () {
      const original = PerformanceState();
      final withError = original.copyWith(errorMessage: 'Failed');
      expect(withError.errorMessage, 'Failed');
      expect(original.errorMessage, isNull);
    });
  });
}
