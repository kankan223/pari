import 'package:civic_commons/performance/data/in_memory_performance_repository.dart';
import 'package:civic_commons/performance/domain/performance_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryPerformanceRepository - Task 12.1', () {
    late InMemoryPerformanceRepository repo;

    setUp(() {
      repo = InMemoryPerformanceRepository();
    });

    test('getMetrics returns initial zero metrics', () async {
      final metrics = await repo.getMetrics();
      expect(metrics, const PerformanceMetrics());
    });

    test('recordColdStart updates cold start time', () async {
      await repo.recordColdStart(450);
      final metrics = await repo.getMetrics();
      expect(metrics.coldStartMs, 450);
    });

    test('recordWarmStart updates warm start time', () async {
      await repo.recordWarmStart(120);
      final metrics = await repo.getMetrics();
      expect(metrics.warmStartMs, 120);
    });

    test('recordMemoryUsage updates memory and peak', () async {
      await repo.recordMemoryUsage(1024 * 1024);
      final metrics = await repo.getMetrics();
      expect(metrics.memoryUsageBytes, 1024 * 1024);
      expect(metrics.peakMemoryBytes, 1024 * 1024);
    });

    test('updatePeakMemory only updates when current exceeds peak', () async {
      await repo.recordMemoryUsage(1024);
      await repo.updatePeakMemory(512);
      final metrics = await repo.getMetrics();
      expect(metrics.peakMemoryBytes, 1024);

      await repo.updatePeakMemory(2048);
      final updated = await repo.getMetrics();
      expect(updated.peakMemoryBytes, 2048);
    });

    test('recordImageCacheUpdate updates cache stats', () async {
      await repo.recordImageCacheUpdate(count: 5, totalBytes: 10240);
      final metrics = await repo.getMetrics();
      expect(metrics.cachedImageCount, 5);
      expect(metrics.cachedImageBytes, 10240);
    });

    test('recordLazyLoadedCount updates lazy loaded count', () async {
      await repo.recordLazyLoadedCount(15);
      final metrics = await repo.getMetrics();
      expect(metrics.lazyLoadedCount, 15);
    });

    test('recordDeferredLoad increments deferred loads', () async {
      await repo.recordDeferredLoad();
      await repo.recordDeferredLoad();
      final metrics = await repo.getMetrics();
      expect(metrics.deferredLoadsCompleted, 2);
    });

    test('constructor accepts initial metrics', () async {
      const initial = PerformanceMetrics(coldStartMs: 300);
      final custom = InMemoryPerformanceRepository(initial: initial);
      final metrics = await custom.getMetrics();
      expect(metrics.coldStartMs, 300);
    });

    test('current getter returns same metrics', () async {
      await repo.recordColdStart(500);
      expect(repo.current.coldStartMs, 500);
    });
  });
}
