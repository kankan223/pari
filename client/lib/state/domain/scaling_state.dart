import '../../scaling/domain/load_test_scenario.dart';
import '../../scaling/domain/scaling_metrics.dart';

/// Phases of the scaling metrics lifecycle.
enum ScalingPhase {
  /// Initial state before any load test.
  idle,

  /// Load test is running.
  running,

  /// Metrics are available.
  ready,

  /// An error occurred during load test.
  error,
}

/// UI-safe scaling state projection (Task 12.4).
///
/// Contains only public metrics — no identity, no PII, no raw URLs.
class ScalingState {
  final ScalingPhase phase;
  final ScalingMetrics metrics;
  final LoadTestScenario? currentScenario;
  final List<LoadTestScenario> availableScenarios;
  final String? errorMessage;

  const ScalingState({
    this.phase = ScalingPhase.idle,
    this.metrics = const ScalingMetrics(),
    this.currentScenario,
    this.availableScenarios = defaultLoadTestScenarios,
    this.errorMessage,
  });

  /// Creates a copy with updated values.
  ScalingState copyWith({
    ScalingPhase? phase,
    ScalingMetrics? metrics,
    LoadTestScenario? currentScenario,
    List<LoadTestScenario>? availableScenarios,
    String? errorMessage,
  }) {
    return ScalingState(
      phase: phase ?? this.phase,
      metrics: metrics ?? this.metrics,
      currentScenario: currentScenario ?? this.currentScenario,
      availableScenarios: availableScenarios ?? this.availableScenarios,
      errorMessage: errorMessage,
    );
  }

  /// Whether the 10,000 concurrent user target is met.
  bool get concurrencyTargetMet => metrics.meetsConcurrencyTarget;

  /// Whether latency target (<200ms avg) is met.
  bool get latencyTargetMet => metrics.latencyTargetMet;

  /// Whether all shards are healthy.
  bool get allShardsHealthy => metrics.allShardsHealthy;

  /// Success rate percentage (0-100).
  double get successRatePercent {
    final rate = metrics.successRate;
    return rate.isNaN ? 0 : rate * 100;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScalingState &&
          runtimeType == other.runtimeType &&
          phase == other.phase &&
          metrics == other.metrics &&
          errorMessage == other.errorMessage;

  @override
  int get hashCode => Object.hash(phase, metrics, errorMessage);
}
