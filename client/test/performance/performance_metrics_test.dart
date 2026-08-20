import 'package:civic_commons/performance/domain/performance_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PerformanceMetrics - Task 12.1', () {
    test('default metrics have zero values', () {
      const metrics = PerformanceMetrics();
      expect(metrics.coldStartMs, 0);
      expect(metrics.warmStartMs, 0);
      expect(metrics.memoryUsageBytes, 0);
      expect(metrics.peakMemoryBytes, 0);
      expect(metrics.cachedImageCount, 0);
      expect(metrics.cachedImageBytes, 0);
      expect(metrics.lazyLoadedCount, 0);
      expect(metrics.deferredLoadsCompleted, 0);
    });

    test('copyWith creates new instance with updated values', () {
      const original = PerformanceMetrics();
      final updated = original.copyWith(coldStartMs: 450, warmStartMs: 120);
      expect(updated.coldStartMs, 450);
      expect(updated.warmStartMs, 120);
      expect(original.coldStartMs, 0); // Original unchanged
    });

    test('coldStartTargetMet returns true when under 600ms', () {
      const fast = PerformanceMetrics(coldStartMs: 450);
      expect(fast.coldStartTargetMet, true);
    });

    test('coldStartTargetMet returns false when over 600ms', () {
      const slow = PerformanceMetrics(coldStartMs: 800);
      expect(slow.coldStartTargetMet, false);
    });

    test('coldStartTargetMet returns false when zero', () {
      const notMeasured = PerformanceMetrics(coldStartMs: 0);
      expect(notMeasured.coldStartTargetMet, false);
    });

    test('memoryUsageMB converts bytes to megabytes', () {
      const metrics = PerformanceMetrics(memoryUsageBytes: 50 * 1024 * 1024);
      expect(metrics.memoryUsageMB, 50.0);
    });

    test('peakMemoryMB converts bytes to megabytes', () {
      const metrics = PerformanceMetrics(peakMemoryBytes: 100 * 1024 * 1024);
      expect(metrics.peakMemoryMB, 100.0);
    });

    test('equality compares all fields', () {
      const a = PerformanceMetrics(coldStartMs: 100, memoryUsageBytes: 1024);
      const b = PerformanceMetrics(coldStartMs: 100, memoryUsageBytes: 1024);
      const c = PerformanceMetrics(coldStartMs: 200, memoryUsageBytes: 1024);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent for equal instances', () {
      const a = PerformanceMetrics(coldStartMs: 100);
      const b = PerformanceMetrics(coldStartMs: 100);
      expect(a.hashCode, b.hashCode);
    });

    test('multiple copyWith calls compose correctly', () {
      const original = PerformanceMetrics();
      final result = original
          .copyWith(coldStartMs: 450)
          .copyWith(memoryUsageBytes: 1024)
          .copyWith(cachedImageCount: 5);
      expect(result.coldStartMs, 450);
      expect(result.memoryUsageBytes, 1024);
      expect(result.cachedImageCount, 5);
    });
  });
}
