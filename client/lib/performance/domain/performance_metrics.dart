/// Performance metrics collected during app lifecycle (Task 12.1).
///
/// Tracks startup time, memory usage, and load times for optimization.
/// All values are pure integers — no identity, no PII.
class PerformanceMetrics {
  /// Cold start time in milliseconds.
  final int coldStartMs;

  /// Warm start time in milliseconds.
  final int warmStartMs;

  /// Current memory usage in bytes.
  final int memoryUsageBytes;

  /// Peak memory usage in bytes during session.
  final int peakMemoryBytes;

  /// Number of images currently cached.
  final int cachedImageCount;

  /// Total size of cached images in bytes.
  final int cachedImageBytes;

  /// Number of items currently lazy-loaded.
  final int lazyLoadedCount;

  /// Number of deferred pillar loads completed.
  final int deferredLoadsCompleted;

  const PerformanceMetrics({
    this.coldStartMs = 0,
    this.warmStartMs = 0,
    this.memoryUsageBytes = 0,
    this.peakMemoryBytes = 0,
    this.cachedImageCount = 0,
    this.cachedImageBytes = 0,
    this.lazyLoadedCount = 0,
    this.deferredLoadsCompleted = 0,
  });

  /// Creates a copy with updated values.
  PerformanceMetrics copyWith({
    int? coldStartMs,
    int? warmStartMs,
    int? memoryUsageBytes,
    int? peakMemoryBytes,
    int? cachedImageCount,
    int? cachedImageBytes,
    int? lazyLoadedCount,
    int? deferredLoadsCompleted,
  }) {
    return PerformanceMetrics(
      coldStartMs: coldStartMs ?? this.coldStartMs,
      warmStartMs: warmStartMs ?? this.warmStartMs,
      memoryUsageBytes: memoryUsageBytes ?? this.memoryUsageBytes,
      peakMemoryBytes: peakMemoryBytes ?? this.peakMemoryBytes,
      cachedImageCount: cachedImageCount ?? this.cachedImageCount,
      cachedImageBytes: cachedImageBytes ?? this.cachedImageBytes,
      lazyLoadedCount: lazyLoadedCount ?? this.lazyLoadedCount,
      deferredLoadsCompleted:
          deferredLoadsCompleted ?? this.deferredLoadsCompleted,
    );
  }

  /// Whether cold start meets the <600ms target.
  bool get coldStartTargetMet => coldStartMs > 0 && coldStartMs < 600;

  /// Memory usage in megabytes (human-readable).
  double get memoryUsageMB => memoryUsageBytes / (1024 * 1024);

  /// Peak memory in megabytes.
  double get peakMemoryMB => peakMemoryBytes / (1024 * 1024);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceMetrics &&
          runtimeType == other.runtimeType &&
          coldStartMs == other.coldStartMs &&
          warmStartMs == other.warmStartMs &&
          memoryUsageBytes == other.memoryUsageBytes &&
          peakMemoryBytes == other.peakMemoryBytes &&
          cachedImageCount == other.cachedImageCount &&
          cachedImageBytes == other.cachedImageBytes &&
          lazyLoadedCount == other.lazyLoadedCount &&
          deferredLoadsCompleted == other.deferredLoadsCompleted;

  @override
  int get hashCode => Object.hash(
        coldStartMs,
        warmStartMs,
        memoryUsageBytes,
        peakMemoryBytes,
        cachedImageCount,
        cachedImageBytes,
        lazyLoadedCount,
        deferredLoadsCompleted,
      );
}
