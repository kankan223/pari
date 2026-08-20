/// Horizontal scaling metrics collected during load tests (Task 12.4).
///
/// Tracks concurrent connections, throughput, latency, and shard health.
/// All values are pure integers — no identity, no PII.
class ScalingMetrics {
  /// Current number of active connections.
  final int activeConnections;

  /// Peak concurrent connections observed.
  final int peakConnections;

  /// Total requests completed in this session.
  final int totalRequests;

  /// Requests completed per second.
  final double requestsPerSecond;

  /// Average latency in milliseconds.
  final int avgLatencyMs;

  /// 95th percentile latency in milliseconds.
  final int p95LatencyMs;

  /// 99th percentile latency in milliseconds.
  final int p99LatencyMs;

  /// Number of successful requests.
  final int successfulRequests;

  /// Number of failed requests.
  final int failedRequests;

  /// Number of healthy shards.
  final int healthyShards;

  /// Total number of shards.
  final int totalShards;

  /// Average shard load factor (0.0 to 1.0).
  final double avgShardLoad;

  const ScalingMetrics({
    this.activeConnections = 0,
    this.peakConnections = 0,
    this.totalRequests = 0,
    this.requestsPerSecond = 0,
    this.avgLatencyMs = 0,
    this.p95LatencyMs = 0,
    this.p99LatencyMs = 0,
    this.successfulRequests = 0,
    this.failedRequests = 0,
    this.healthyShards = 0,
    this.totalShards = 0,
    this.avgShardLoad = 0,
  });

  /// Creates a copy with updated values.
  ScalingMetrics copyWith({
    int? activeConnections,
    int? peakConnections,
    int? totalRequests,
    double? requestsPerSecond,
    int? avgLatencyMs,
    int? p95LatencyMs,
    int? p99LatencyMs,
    int? successfulRequests,
    int? failedRequests,
    int? healthyShards,
    int? totalShards,
    double? avgShardLoad,
  }) {
    return ScalingMetrics(
      activeConnections: activeConnections ?? this.activeConnections,
      peakConnections: peakConnections ?? this.peakConnections,
      totalRequests: totalRequests ?? this.totalRequests,
      requestsPerSecond: requestsPerSecond ?? this.requestsPerSecond,
      avgLatencyMs: avgLatencyMs ?? this.avgLatencyMs,
      p95LatencyMs: p95LatencyMs ?? this.p95LatencyMs,
      p99LatencyMs: p99LatencyMs ?? this.p99LatencyMs,
      successfulRequests: successfulRequests ?? this.successfulRequests,
      failedRequests: failedRequests ?? this.failedRequests,
      healthyShards: healthyShards ?? this.healthyShards,
      totalShards: totalShards ?? this.totalShards,
      avgShardLoad: avgShardLoad ?? this.avgShardLoad,
    );
  }

  /// Success rate (0.0 to 1.0).
  double get successRate =>
      totalRequests > 0 ? successfulRequests / totalRequests : double.nan;

  /// Whether the system is meeting the 10,000 concurrent user target.
  bool get meetsConcurrencyTarget => peakConnections >= 10000;

  /// Whether latency is within acceptable bounds (<200ms avg).
  bool get latencyTargetMet => avgLatencyMs > 0 && avgLatencyMs < 200;

  /// Whether all shards are healthy.
  bool get allShardsHealthy => totalShards > 0 && healthyShards == totalShards;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScalingMetrics &&
          runtimeType == other.runtimeType &&
          activeConnections == other.activeConnections &&
          peakConnections == other.peakConnections &&
          totalRequests == other.totalRequests;

  @override
  int get hashCode => Object.hash(
        activeConnections,
        peakConnections,
        totalRequests,
      );
}
