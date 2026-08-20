/// CDN delivery metrics collected during content downloads (Task 12.3).
///
/// Tracks Time to First Byte, bandwidth saved by caching, cache hit ratio,
/// and delivery success rates. All values are pure integers — no identity,
/// no PII.
class DeliveryMetrics {
  /// Time to First Byte in milliseconds (last download).
  final int ttfbMs;

  /// Total bytes downloaded from CDN in this session.
  final int bytesDownloaded;

  /// Total bytes served from local cache (bandwidth saved).
  final int bytesFromCache;

  /// Total number of CDN requests.
  final int totalRequests;

  /// Number of cache hits.
  final int cacheHits;

  /// Number of failed downloads.
  final int failedDownloads;

  /// Average download speed in bytes per second.
  final int avgDownloadSpeedBps;

  /// Total time spent downloading in milliseconds.
  final int totalDownloadTimeMs;

  const DeliveryMetrics({
    this.ttfbMs = 0,
    this.bytesDownloaded = 0,
    this.bytesFromCache = 0,
    this.totalRequests = 0,
    this.cacheHits = 0,
    this.failedDownloads = 0,
    this.avgDownloadSpeedBps = 0,
    this.totalDownloadTimeMs = 0,
  });

  /// Creates a copy with updated values.
  DeliveryMetrics copyWith({
    int? ttfbMs,
    int? bytesDownloaded,
    int? bytesFromCache,
    int? totalRequests,
    int? cacheHits,
    int? failedDownloads,
    int? avgDownloadSpeedBps,
    int? totalDownloadTimeMs,
  }) {
    return DeliveryMetrics(
      ttfbMs: ttfbMs ?? this.ttfbMs,
      bytesDownloaded: bytesDownloaded ?? this.bytesDownloaded,
      bytesFromCache: bytesFromCache ?? this.bytesFromCache,
      totalRequests: totalRequests ?? this.totalRequests,
      cacheHits: cacheHits ?? this.cacheHits,
      failedDownloads: failedDownloads ?? this.failedDownloads,
      avgDownloadSpeedBps: avgDownloadSpeedBps ?? this.avgDownloadSpeedBps,
      totalDownloadTimeMs: totalDownloadTimeMs ?? this.totalDownloadTimeMs,
    );
  }

  /// Cache hit ratio (0.0 to 1.0, or NaN if no requests).
  double get cacheHitRatio =>
      totalRequests > 0 ? cacheHits / totalRequests : double.nan;

  /// Bandwidth saved ratio (bytes from cache / total bytes).
  double get bandwidthSavedRatio {
    final total = bytesDownloaded + bytesFromCache;
    return total > 0 ? bytesFromCache / total : double.nan;
  }

  /// Total bytes served (downloaded + cached).
  int get totalBytesServed => bytesDownloaded + bytesFromCache;

  /// Whether cache hit ratio meets the >80% target.
  bool get cacheHitTargetMet => totalRequests >= 10 && cacheHitRatio > 0.8;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeliveryMetrics &&
          runtimeType == other.runtimeType &&
          ttfbMs == other.ttfbMs &&
          bytesDownloaded == other.bytesDownloaded &&
          bytesFromCache == other.bytesFromCache &&
          totalRequests == other.totalRequests &&
          cacheHits == other.cacheHits &&
          failedDownloads == other.failedDownloads;

  @override
  int get hashCode => Object.hash(
        ttfbMs,
        bytesDownloaded,
        bytesFromCache,
        totalRequests,
        cacheHits,
        failedDownloads,
      );
}
