import 'cdn_delivery_state.dart';

/// Port for the CDN delivery metrics BLoC (Task 12.3).
///
/// Handles delivery metrics collection, CDN config management, and
/// edge cache rule tracking. No identity, no PII.
abstract class CdnDeliveryBloc {
  /// Current state stream.
  Stream<CdnDeliveryState> get state;

  /// Current state value.
  CdnDeliveryState get current;

  /// Starts collecting delivery metrics.
  void startMeasuring();

  /// Records a cache hit.
  void recordCacheHit(int bytesServed);

  /// Records a CDN download.
  void recordDownload({
    required int bytesDownloaded,
    required int ttfbMs,
    required int downloadTimeMs,
  });

  /// Records a failed download.
  void recordFailure();

  /// Refreshes metrics from the repository.
  Future<void> refresh();

  /// Disposes resources.
  void close();
}
