import 'delivery_metrics.dart';

/// Port for CDN content delivery operations (Task 12.3).
///
/// Implementations resolve presigned URLs, fetch content from edge,
/// and track delivery metrics. All networking is isolated to the data
/// layer — this port contains no networking imports.
abstract class CdnRepository {
  /// Resolves a presigned URL for a module asset.
  ///
  /// Returns the presigned URL string, or throws on failure.
  Future<String> resolvePresignedUrl({
    required String moduleId,
    required String assetPath,
  });

  /// Downloads content from a presigned URL and returns sealed bytes.
  ///
  /// The content is sealed with AES-256-GCM before returning.
  Future<List<int>> downloadAndSeal({
    required String presignedUrl,
    required int expectedSizeBytes,
  });

  /// Returns current delivery metrics.
  Future<DeliveryMetrics> getMetrics();

  /// Records a cache hit (content served from local cache).
  Future<void> recordCacheHit(int bytesServed);

  /// Records a CDN download (content fetched from edge).
  Future<void> recordDownload({
    required int bytesDownloaded,
    required int ttfbMs,
    required int downloadTimeMs,
  });

  /// Records a failed download.
  Future<void> recordFailure();

  /// Clears all delivery metrics.
  Future<void> clearMetrics();
}
