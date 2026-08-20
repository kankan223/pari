import '../domain/cdn_fetcher.dart';

/// In-memory implementation of [CdnFetcher] for tests (Task 12.3).
///
/// Simulates network fetches with configurable delays and failures.
class InMemoryCdnFetcher implements CdnFetcher {
  int _lastTtfbMs = 0;
  int _totalBytesDownloaded = 0;

  /// Whether to simulate a failure on the next fetch.
  bool simulateFailure = false;

  /// Simulated TTFB in milliseconds for the next fetch.
  int simulatedTtfbMs = 50;

  @override
  int get lastTtfbMs => _lastTtfbMs;

  @override
  int get totalBytesDownloaded => _totalBytesDownloaded;

  @override
  Future<List<int>> fetchBytes(
    String url, {
    required int expectedSizeBytes,
  }) async {
    if (simulateFailure) {
      simulateFailure = false;
      throw StateError('Simulated CDN fetch failure');
    }
    _lastTtfbMs = simulatedTtfbMs;
    _totalBytesDownloaded += expectedSizeBytes;
    return List.filled(expectedSizeBytes, 0xCD);
  }

  @override
  Future<List<int>> fetchAndSeal(
    String url, {
    required int expectedSizeBytes,
  }) async {
    if (simulateFailure) {
      simulateFailure = false;
      throw StateError('Simulated CDN fetch failure');
    }
    _lastTtfbMs = simulatedTtfbMs;
    _totalBytesDownloaded += expectedSizeBytes;
    // Simulate sealed content (in production, this uses AES-256-GCM)
    return List.filled(expectedSizeBytes, 0xAB);
  }

  /// Resets metrics for test isolation.
  void reset() {
    _lastTtfbMs = 0;
    _totalBytesDownloaded = 0;
    simulateFailure = false;
    simulatedTtfbMs = 50;
  }
}
