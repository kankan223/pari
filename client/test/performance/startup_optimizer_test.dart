import 'package:civic_commons/performance/domain/startup_optimizer.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civic_commons/performance/data/in_memory_startup_optimizer.dart';

void main() {
  group('DeferredPillar - Task 12.1', () {
    test('default pillar is notStarted', () {
      const pillar = DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      );
      expect(pillar.state, DeferredPillarState.notStarted);
      expect(pillar.isReady, false);
      expect(pillar.requested, false);
      expect(pillar.loadDurationMs, isNull);
    });

    test('copyWith updates state', () {
      const original = DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      );
      final loading = original.copyWith(
        state: DeferredPillarState.loading,
        loadingStartedAt: 1000,
      );
      expect(loading.state, DeferredPillarState.loading);
      expect(loading.loadingStartedAt, 1000);
      expect(original.state, DeferredPillarState.notStarted);
    });

    test('isReady returns true only when state is ready', () {
      const notReady = DeferredPillar(
        pillarId: 'x',
        displayName: 'X',
        state: DeferredPillarState.loading,
      );
      const ready = DeferredPillar(
        pillarId: 'x',
        displayName: 'X',
        state: DeferredPillarState.ready,
      );
      expect(notReady.isReady, false);
      expect(ready.isReady, true);
    });

    test('loadDurationMs computes duration when timestamps exist', () {
      const pillar = DeferredPillar(
        pillarId: 'x',
        displayName: 'X',
        loadingStartedAt: 1000,
        loadingCompletedAt: 1500,
      );
      expect(pillar.loadDurationMs, 500);
      expect(pillar.hasLoadDuration, true);
    });

    test('loadDurationMs is null without timestamps', () {
      const pillar = DeferredPillar(
        pillarId: 'x',
        displayName: 'X',
      );
      expect(pillar.loadDurationMs, isNull);
      expect(pillar.hasLoadDuration, false);
    });

    test('equality by pillarId and state', () {
      const a = DeferredPillar(
          pillarId: 'vault',
          displayName: 'V',
          state: DeferredPillarState.ready);
      const b = DeferredPillar(
          pillarId: 'vault',
          displayName: 'V',
          state: DeferredPillarState.ready);
      const c = DeferredPillar(
          pillarId: 'vault',
          displayName: 'V',
          state: DeferredPillarState.loading);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('InMemoryStartupOptimizer - Task 12.1', () {
    late InMemoryStartupOptimizer optimizer;

    setUp(() {
      optimizer = InMemoryStartupOptimizer();
    });

    test('register adds a pillar', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      expect(optimizer.pillars, hasLength(1));
      expect(optimizer.getPillar('vault'), isNotNull);
    });

    test('requestPillar marks pillar as requested', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      optimizer.requestPillar('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.requested, true);
    });

    test('startLoading changes state to loading', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      optimizer.startLoading('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.state, DeferredPillarState.loading);
      expect(pillar.loadingStartedAt, isNotNull);
    });

    test('completeLoading changes state to ready', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      optimizer.startLoading('vault');
      optimizer.completeLoading('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.state, DeferredPillarState.ready);
      expect(pillar.loadingCompletedAt, isNotNull);
    });

    test('markFailed changes state to failed', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
      ));
      optimizer.startLoading('vault');
      optimizer.markFailed('vault');
      final pillar = optimizer.getPillar('vault')!;
      expect(pillar.state, DeferredPillarState.failed);
    });

    test('pillarsByPriority sorts by priority ascending', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'warroom',
        displayName: 'War Room',
        priority: 3,
      ));
      optimizer.register(const DeferredPillar(
        pillarId: 'vault',
        displayName: 'Vault',
        priority: 1,
      ));
      optimizer.register(const DeferredPillar(
        pillarId: 'academy',
        displayName: 'Academy',
        priority: 2,
      ));
      final sorted = optimizer.pillarsByPriority;
      expect(sorted.map((p) => p.pillarId), ['vault', 'academy', 'warroom']);
    });

    test('readyPillars returns only ready pillars', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'a',
        displayName: 'A',
      ));
      optimizer.register(const DeferredPillar(
        pillarId: 'b',
        displayName: 'B',
      ));
      optimizer.startLoading('a');
      optimizer.completeLoading('a');
      expect(optimizer.readyPillars, hasLength(1));
      expect(optimizer.readyPillars.first.pillarId, 'a');
    });

    test('pendingRequestedPillars returns requested notStarted', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'a',
        displayName: 'A',
      ));
      optimizer.requestPillar('a');
      expect(optimizer.pendingRequestedPillars, hasLength(1));

      optimizer.startLoading('a');
      expect(optimizer.pendingRequestedPillars, isEmpty);
    });

    test('reset clears all pillar states', () {
      optimizer.register(const DeferredPillar(
        pillarId: 'a',
        displayName: 'A',
      ));
      optimizer.startLoading('a');
      optimizer.completeLoading('a');
      optimizer.reset();
      final pillar = optimizer.getPillar('a')!;
      expect(pillar.state, DeferredPillarState.notStarted);
      // reset() clears timestamps
      expect(pillar.loadingCompletedAt, isNull);
    });

    test('getPillar returns null for unknown pillar', () {
      expect(optimizer.getPillar('unknown'), isNull);
    });

    test('requestPillar on unknown pillar is a no-op', () {
      optimizer.requestPillar('unknown');
      expect(optimizer.pillars, isEmpty);
    });
  });
}
