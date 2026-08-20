import '../../scaling/domain/load_test_scenario.dart';
import 'scaling_state.dart';

/// Port for the horizontal scaling metrics BLoC (Task 12.4).
///
/// Handles load test execution, scaling metrics collection, and
/// shard health monitoring. No identity, no PII.
abstract class ScalingBloc {
  /// Current state stream.
  Stream<ScalingState> get state;

  /// Current state value.
  ScalingState get current;

  /// Starts collecting scaling metrics.
  void startMeasuring();

  /// Runs a load test scenario.
  Future<void> runLoadTest(LoadTestScenario scenario);

  /// Records a request completion.
  void recordRequest({
    required bool success,
    required int latencyMs,
    required String shardId,
  });

  /// Records a connection event.
  void recordConnection({required bool opened});

  /// Refreshes metrics from the repository.
  Future<void> refresh();

  /// Disposes resources.
  void close();
}
