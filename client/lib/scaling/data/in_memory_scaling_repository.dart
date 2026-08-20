import '../domain/connection_pool_config.dart';
import '../domain/load_test_scenario.dart';
import '../domain/scaling_metrics.dart';
import '../domain/scaling_repository.dart';

/// In-memory implementation of [ScalingRepository] for tests (Task 12.4).
///
/// Tracks scaling metrics and simulates load test execution.
class InMemoryScalingRepository implements ScalingRepository {
  ScalingMetrics _metrics;
  final ConnectionPoolConfig _config;
  final List<LoadTestResult> _testResults = [];

  InMemoryScalingRepository({
    ScalingMetrics? initialMetrics,
    ConnectionPoolConfig? config,
  })  : _metrics = initialMetrics ?? const ScalingMetrics(),
        _config = config ?? const ConnectionPoolConfig();

  /// History of completed load tests (for test verification).
  List<LoadTestResult> get testResults => List.unmodifiable(_testResults);

  @override
  Future<ScalingMetrics> runLoadTest(LoadTestScenario scenario) async {
    // Simulate load test execution
    final result = LoadTestResult(
      scenarioId: scenario.id,
      scenarioName: scenario.name,
      concurrentUsers: scenario.concurrentUsers,
      totalRequests: scenario.totalRequests,
      successfulRequests: (scenario.totalRequests * 0.95).round(),
      failedRequests: (scenario.totalRequests * 0.05).round(),
      avgLatencyMs: 50 + (scenario.concurrentUsers ~/ 100),
      p95LatencyMs: 100 + (scenario.concurrentUsers ~/ 50),
      p99LatencyMs: 200 + (scenario.concurrentUsers ~/ 25),
      durationMs: scenario.estimatedDurationMs,
    );
    _testResults.add(result);

    // Update metrics with test results
    _metrics = ScalingMetrics(
      activeConnections: scenario.concurrentUsers,
      peakConnections: scenario.concurrentUsers,
      totalRequests: result.totalRequests,
      requestsPerSecond: result.totalRequests / (result.durationMs / 1000),
      avgLatencyMs: result.avgLatencyMs,
      p95LatencyMs: result.p95LatencyMs,
      p99LatencyMs: result.p99LatencyMs,
      successfulRequests: result.successfulRequests,
      failedRequests: result.failedRequests,
      healthyShards: 10,
      totalShards: 10,
      avgShardLoad: scenario.concurrentUsers / 10000,
    );

    return _metrics;
  }

  @override
  Future<ScalingMetrics> getMetrics() async => _metrics;

  @override
  Future<void> recordRequest({
    required bool success,
    required int latencyMs,
    required String shardId,
  }) async {
    final total = _metrics.totalRequests + 1;
    final successful =
        success ? _metrics.successfulRequests + 1 : _metrics.successfulRequests;
    final failed =
        !success ? _metrics.failedRequests + 1 : _metrics.failedRequests;

    // Update average latency
    final totalTime =
        _metrics.avgLatencyMs * _metrics.totalRequests + latencyMs;
    final avgLatency = total > 0 ? (totalTime ~/ total) : 0;

    _metrics = _metrics.copyWith(
      totalRequests: total,
      successfulRequests: successful,
      failedRequests: failed,
      avgLatencyMs: avgLatency,
    );
  }

  @override
  Future<void> recordConnection({required bool opened}) async {
    final current = _metrics.activeConnections;
    final newCount = opened ? current + 1 : (current - 1).clamp(0, current);
    final peak = newCount > _metrics.peakConnections
        ? newCount
        : _metrics.peakConnections;

    _metrics = _metrics.copyWith(
      activeConnections: newCount,
      peakConnections: peak,
    );
  }

  @override
  Future<void> updateShardHealth({
    required String shardId,
    required bool healthy,
    required double loadFactor,
  }) async {
    // In-memory: just track the update
  }

  @override
  Future<void> clearMetrics() async {
    _metrics = const ScalingMetrics();
    _testResults.clear();
  }

  @override
  ConnectionPoolConfig getConfig() => _config;
}

/// Result of a completed load test (Task 12.4).
class LoadTestResult {
  final String scenarioId;
  final String scenarioName;
  final int concurrentUsers;
  final int totalRequests;
  final int successfulRequests;
  final int failedRequests;
  final int avgLatencyMs;
  final int p95LatencyMs;
  final int p99LatencyMs;
  final int durationMs;

  const LoadTestResult({
    required this.scenarioId,
    required this.scenarioName,
    required this.concurrentUsers,
    required this.totalRequests,
    required this.successfulRequests,
    required this.failedRequests,
    required this.avgLatencyMs,
    required this.p95LatencyMs,
    required this.p99LatencyMs,
    required this.durationMs,
  });

  /// Success rate (0.0 to 1.0).
  double get successRate =>
      totalRequests > 0 ? successfulRequests / totalRequests : 0;

  /// Requests per second.
  double get requestsPerSecond =>
      durationMs > 0 ? totalRequests / (durationMs / 1000) : 0;
}
