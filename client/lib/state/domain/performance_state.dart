import '../../performance/domain/performance_metrics.dart';
import '../../performance/domain/startup_optimizer.dart';

/// Phases of the performance monitoring lifecycle.
enum PerformancePhase {
  /// Initial state before measurement.
  idle,

  /// Metrics are being collected.
  measuring,

  /// Metrics are available.
  ready,

  /// An error occurred during measurement.
  error,
}

/// UI-safe performance state projection (Task 12.1).
///
/// Contains only public metrics — no identity, no PII, no raw device data.
class PerformanceState {
  final PerformancePhase phase;
  final PerformanceMetrics metrics;
  final List<DeferredPillar> deferredPillars;
  final String? errorMessage;

  const PerformanceState({
    this.phase = PerformancePhase.idle,
    this.metrics = const PerformanceMetrics(),
    this.deferredPillars = const [],
    this.errorMessage,
  });

  /// Creates a copy with updated values.
  PerformanceState copyWith({
    PerformancePhase? phase,
    PerformanceMetrics? metrics,
    List<DeferredPillar>? deferredPillars,
    String? errorMessage,
  }) {
    return PerformanceState(
      phase: phase ?? this.phase,
      metrics: metrics ?? this.metrics,
      deferredPillars: deferredPillars ?? this.deferredPillars,
      errorMessage: errorMessage,
    );
  }

  /// Whether the cold start target (<600ms) is met.
  bool get coldStartTargetMet => metrics.coldStartTargetMet;

  /// Number of deferred pillars that are ready.
  int get readyPillarCount => deferredPillars.where((p) => p.isReady).length;

  /// Number of deferred pillars that are loading.
  int get loadingPillarCount => deferredPillars
      .where((p) => p.state == DeferredPillarState.loading)
      .length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PerformanceState &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          metrics == other.metrics &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(phase, metrics, errorMessage);
}
