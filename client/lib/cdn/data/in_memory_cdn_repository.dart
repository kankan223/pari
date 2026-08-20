import '../domain/cdn_repository.dart';
import '../domain/delivery_metrics.dart';

/// In-memory implementation of [CdnRepository] for tests (Task 12.3).
///
/// Tracks delivery metrics and simulates presigned URL resolution.
class InMemoryCdnRepository implements CdnRepository {
  DeliveryMetrics _metrics;
  final Map<String, String> _presignedUrls = {};

  InMemoryCdnRepository({DeliveryMetrics? initialMetrics})
      : _metrics = initialMetrics ?? const DeliveryMetrics();

  /// Seeds a presigned URL for testing.
  void seedPresignedUrl(String key, String url) {
    _presignedUrls[key] = url;
  }

  @override
  Future<String> resolvePresignedUrl({
    required String moduleId,
    required String assetPath,
  }) async {
    final key = '$moduleId/$assetPath';
    final url = _presignedUrls[key];
    if (url == null) {
      throw StateError('No presigned URL for $key');
    }
    return url;
  }

  @override
  Future<List<int>> downloadAndSeal({
    required String presignedUrl,
    required int expectedSizeBytes,
  }) async {
    // Simulate sealed content (in production, this uses AES-256-GCM)
    return List.filled(expectedSizeBytes, 0xAB);
  }

  @override
  Future<DeliveryMetrics> getMetrics() async => _metrics;

  @override
  Future<void> recordCacheHit(int bytesServed) async {
    _metrics = _metrics.copyWith(
      bytesFromCache: _metrics.bytesFromCache + bytesServed,
      totalRequests: _metrics.totalRequests + 1,
      cacheHits: _metrics.cacheHits + 1,
    );
  }

  @override
  Future<void> recordDownload({
    required int bytesDownloaded,
    required int ttfbMs,
    required int downloadTimeMs,
  }) async {
    final totalBytes = _metrics.bytesDownloaded + bytesDownloaded;
    final totalTime = _metrics.totalDownloadTimeMs + downloadTimeMs;
    final avgSpeed = totalTime > 0 ? (totalBytes * 1000 ~/ totalTime) : 0;

    _metrics = _metrics.copyWith(
      ttfbMs: ttfbMs,
      bytesDownloaded: totalBytes,
      totalRequests: _metrics.totalRequests + 1,
      avgDownloadSpeedBps: avgSpeed,
      totalDownloadTimeMs: totalTime,
    );
  }

  @override
  Future<void> recordFailure() async {
    _metrics = _metrics.copyWith(
      failedDownloads: _metrics.failedDownloads + 1,
    );
  }

  @override
  Future<void> clearMetrics() async {
    _metrics = const DeliveryMetrics();
  }
}
