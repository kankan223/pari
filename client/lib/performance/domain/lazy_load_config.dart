/// Configuration for lazy loading behavior (Task 12.1).
///
/// Defines viewport thresholds and batch sizes for deferred image/video
/// loading. All values are pure and deterministic — no identity, no PII.
class LazyLoadConfig {
  /// How many items beyond the visible viewport to pre-load (default: 3).
  final int preloadItemCount;

  /// Maximum number of concurrent image loads (default: 4).
  final int maxConcurrentLoads;

  /// Threshold in pixels from viewport edge before loading triggers.
  final double viewportThresholdPx;

  /// Maximum cache size in bytes for decoded images (default: 50 MB).
  final int maxImageCacheBytes;

  /// Maximum number of items in the LRU image cache.
  final int maxImageCacheCount;

  const LazyLoadConfig({
    this.preloadItemCount = 3,
    this.maxConcurrentLoads = 4,
    this.viewportThresholdPx = 200.0,
    this.maxImageCacheBytes = 50 * 1024 * 1024,
    this.maxImageCacheCount = 100,
  });

  /// Conservative config for low-end devices.
  const LazyLoadConfig.conservative()
      : preloadItemCount = 1,
        maxConcurrentLoads = 2,
        viewportThresholdPx = 100.0,
        maxImageCacheBytes = 20 * 1024 * 1024,
        maxImageCacheCount = 50;

  /// Aggressive config for high-end devices.
  const LazyLoadConfig.aggressive()
      : preloadItemCount = 5,
        maxConcurrentLoads = 8,
        viewportThresholdPx = 400.0,
        maxImageCacheBytes = 100 * 1024 * 1024,
        maxImageCacheCount = 200;
}
