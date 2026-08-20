/// Port for raw CDN fetch operations (Task 12.3).
///
/// This is the ONLY networking seam in the CDN module. The data layer
/// implementation handles HTTP requests, while the domain and UI layers
/// remain networking-free. All implementations must seal content before
/// returning it.
abstract class CdnFetcher {
  /// Fetches content from a URL and returns raw bytes.
  ///
  /// Throws on network failure, timeout, or HTTP error.
  Future<List<int>> fetchBytes(String url, {required int expectedSizeBytes});

  /// Fetches content and returns it sealed with AES-256-GCM.
  ///
  /// The plaintext bytes never leave this method — only ciphertext is returned.
  Future<List<int>> fetchAndSeal(String url, {required int expectedSizeBytes});

  /// Returns the Time to Last Byte for the last fetch in milliseconds.
  int get lastTtfbMs;

  /// Returns the total bytes downloaded in this session.
  int get totalBytesDownloaded;
}
