import 'performance_metrics.dart';

/// Port for persisting performance metrics and managing lazy load state.
///
/// Implementations store metrics locally (SQLCipher or in-memory for tests).
/// No identity, no PII — only performance counters.
abstract class PerformanceRepository {
  /// Returns the current performance metrics snapshot.
  Future<PerformanceMetrics> getMetrics();

  /// Updates the cold start time (called once at app launch).
  Future<void> recordColdStart(int milliseconds);

  /// Updates the warm start time (called on resume from background).
  Future<void> recordWarmStart(int milliseconds);

  /// Records current memory usage.
  Future<void> recordMemoryUsage(int bytes);

  /// Updates peak memory if current exceeds recorded peak.
  Future<void> updatePeakMemory(int currentBytes);

  /// Records an image cache event (count change, size change).
  Future<void> recordImageCacheUpdate(
      {required int count, required int totalBytes});

  /// Records a lazy-loaded item count change.
  Future<void> recordLazyLoadedCount(int count);

  /// Records a deferred pillar load completion.
  Future<void> recordDeferredLoad();
}
