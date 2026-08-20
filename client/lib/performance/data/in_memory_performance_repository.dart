import '../domain/performance_metrics.dart';
import '../domain/performance_repository.dart';

/// In-memory implementation of [PerformanceRepository] (Task 12.1).
///
/// Used for tests and the manual testing harness.
class InMemoryPerformanceRepository implements PerformanceRepository {
  PerformanceMetrics _metrics;

  InMemoryPerformanceRepository({PerformanceMetrics? initial})
      : _metrics = initial ?? const PerformanceMetrics();

  @override
  Future<PerformanceMetrics> getMetrics() async => _metrics;

  @override
  Future<void> recordColdStart(int milliseconds) async {
    _metrics = _metrics.copyWith(coldStartMs: milliseconds);
  }

  @override
  Future<void> recordWarmStart(int milliseconds) async {
    _metrics = _metrics.copyWith(warmStartMs: milliseconds);
  }

  @override
  Future<void> recordMemoryUsage(int bytes) async {
    _metrics = _metrics.copyWith(memoryUsageBytes: bytes);
    if (bytes > _metrics.peakMemoryBytes) {
      _metrics = _metrics.copyWith(peakMemoryBytes: bytes);
    }
  }

  @override
  Future<void> updatePeakMemory(int currentBytes) async {
    if (currentBytes > _metrics.peakMemoryBytes) {
      _metrics = _metrics.copyWith(peakMemoryBytes: currentBytes);
    }
  }

  @override
  Future<void> recordImageCacheUpdate({
    required int count,
    required int totalBytes,
  }) async {
    _metrics = _metrics.copyWith(
      cachedImageCount: count,
      cachedImageBytes: totalBytes,
    );
  }

  @override
  Future<void> recordLazyLoadedCount(int count) async {
    _metrics = _metrics.copyWith(lazyLoadedCount: count);
  }

  @override
  Future<void> recordDeferredLoad() async {
    _metrics = _metrics.copyWith(
      deferredLoadsCompleted: _metrics.deferredLoadsCompleted + 1,
    );
  }

  /// Expose current metrics for testing.
  PerformanceMetrics get current => _metrics;
}
