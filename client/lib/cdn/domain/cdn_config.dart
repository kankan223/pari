/// Configuration for CDN asset resolution and edge caching (Task 12.3).
///
/// Defines how module assets are resolved from CDN endpoints with
/// optimized delivery settings. All values are pure — no identity, no PII.
class CdnConfig {
  /// Base URL for the CDN edge (e.g., Cloudflare R2 or Bunny.net).
  final String edgeBaseUrl;

  /// Presigned URL lifetime in seconds (default: 3600 = 1 hour).
  final int presignedUrlLifetimeSeconds;

  /// Maximum concurrent asset downloads (default: 3).
  final int maxConcurrentDownloads;

  /// Retry count for failed downloads (default: 2).
  final int retryCount;

  /// Base delay between retries in milliseconds (default: 500).
  final int retryBaseDelayMs;

  /// Maximum total download size in bytes (default: 200 MB).
  final int maxDownloadSizeBytes;

  /// Whether to enable HTTP/2 multiplexing (default: true).
  final bool enableHttp2;

  /// Whether to enable Brotli compression at edge (default: true).
  final bool enableBrotli;

  /// Timeout per asset download in seconds (default: 30).
  final int downloadTimeoutSeconds;

  const CdnConfig({
    required this.edgeBaseUrl,
    this.presignedUrlLifetimeSeconds = 3600,
    this.maxConcurrentDownloads = 3,
    this.retryCount = 2,
    this.retryBaseDelayMs = 500,
    this.maxDownloadSizeBytes = 200 * 1024 * 1024,
    this.enableHttp2 = true,
    this.enableBrotli = true,
    this.downloadTimeoutSeconds = 30,
  });

  /// Conservative config for low-bandwidth connections.
  const CdnConfig.conservative()
      : edgeBaseUrl = '',
        presignedUrlLifetimeSeconds = 1800,
        maxConcurrentDownloads = 1,
        retryCount = 3,
        retryBaseDelayMs = 1000,
        maxDownloadSizeBytes = 100 * 1024 * 1024,
        enableHttp2 = true,
        enableBrotli = false,
        downloadTimeoutSeconds = 60;

  /// Aggressive config for high-bandwidth connections.
  const CdnConfig.aggressive()
      : edgeBaseUrl = '',
        presignedUrlLifetimeSeconds = 7200,
        maxConcurrentDownloads = 6,
        retryCount = 1,
        retryBaseDelayMs = 250,
        maxDownloadSizeBytes = 500 * 1024 * 1024,
        enableHttp2 = true,
        enableBrotli = true,
        downloadTimeoutSeconds = 15;
}
