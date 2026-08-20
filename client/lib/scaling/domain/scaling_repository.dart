import 'connection_pool_config.dart';
import 'load_test_scenario.dart';
import 'scaling_metrics.dart';

/// Port for horizontal scaling operations (Task 12.4).
///
/// Implementations handle load test execution, connection pool management,
/// and scaling metrics collection. All networking is isolated to the
/// data layer — this port contains no networking imports.
abstract class ScalingRepository {
  /// Runs a load test scenario and returns final metrics.
  Future<ScalingMetrics> runLoadTest(LoadTestScenario scenario);

  /// Returns current scaling metrics without running a test.
  Future<ScalingMetrics> getMetrics();

  /// Records a request completion (success or failure).
  Future<void> recordRequest({
    required bool success,
    required int latencyMs,
    required String shardId,
  });

  /// Records a connection event (open or close).
  Future<void> recordConnection({required bool opened});

  /// Updates shard health status.
  Future<void> updateShardHealth({
    required String shardId,
    required bool healthy,
    required double loadFactor,
  });

  /// Clears all scaling metrics.
  Future<void> clearMetrics();

  /// Returns the connection pool configuration.
  ConnectionPoolConfig getConfig();
}
