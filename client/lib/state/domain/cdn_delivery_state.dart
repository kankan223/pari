import '../../cdn/domain/cdn_config.dart';
import '../../cdn/domain/delivery_metrics.dart';
import '../../cdn/domain/edge_cache_rule.dart';

/// Phases of the CDN delivery lifecycle.
enum CdnDeliveryPhase {
  /// Initial state before any delivery.
  idle,

  /// Delivery metrics are being collected.
  measuring,

  /// Metrics are available.
  ready,

  /// An error occurred during delivery.
  error,
}

/// UI-safe CDN delivery state projection (Task 12.3).
///
/// Contains only public metrics — no identity, no PII, no raw URLs.
class CdnDeliveryState {
  final CdnDeliveryPhase phase;
  final DeliveryMetrics metrics;
  final CdnConfig config;
  final List<EdgeCacheRule> cacheRules;
  final String? errorMessage;

  const CdnDeliveryState({
    this.phase = CdnDeliveryPhase.idle,
    this.metrics = const DeliveryMetrics(),
    this.config = const CdnConfig(edgeBaseUrl: ''),
    this.cacheRules = defaultEdgeCacheRules,
    this.errorMessage,
  });

  /// Creates a copy with updated values.
  CdnDeliveryState copyWith({
    CdnDeliveryPhase? phase,
    DeliveryMetrics? metrics,
    CdnConfig? config,
    List<EdgeCacheRule>? cacheRules,
    String? errorMessage,
  }) {
    return CdnDeliveryState(
      phase: phase ?? this.phase,
      metrics: metrics ?? this.metrics,
      config: config ?? this.config,
      cacheRules: cacheRules ?? this.cacheRules,
      errorMessage: errorMessage,
    );
  }

  /// Whether the cache hit ratio target (>80%) is met.
  bool get cacheHitTargetMet => metrics.cacheHitTargetMet;

  /// Total bytes served (downloaded + cached).
  int get totalBytesServed => metrics.totalBytesServed;

  /// Bandwidth saved percentage (0-100).
  double get bandwidthSavedPercent {
    final ratio = metrics.bandwidthSavedRatio;
    return ratio.isNaN ? 0 : ratio * 100;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CdnDeliveryState &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          metrics == other.metrics &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(phase, metrics, errorMessage);
}
