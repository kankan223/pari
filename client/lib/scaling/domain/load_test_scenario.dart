/// A load testing scenario for horizontal scaling validation (Task 12.4).
///
/// Defines concurrent users, request patterns, and duration for
/// simulating high-load conditions. All values are pure integers —
/// no identity, no PII.
class LoadTestScenario {
  /// Unique scenario identifier.
  final String id;

  /// Human-readable scenario name.
  final String name;

  /// Number of concurrent virtual users.
  final int concurrentUsers;

  /// Total number of requests per user.
  final int requestsPerUser;

  /// Think time between requests in milliseconds.
  final int thinkTimeMs;

  /// Test duration in seconds (0 = run all requests).
  final int durationSeconds;

  /// Request pattern (e.g., 'constant', 'ramp_up', 'spike').
  final LoadPattern pattern;

  /// Target endpoint type (e.g., 'feed', 'search', 'post').
  final String endpointType;

  const LoadTestScenario({
    required this.id,
    required this.name,
    required this.concurrentUsers,
    this.requestsPerUser = 10,
    this.thinkTimeMs = 100,
    this.durationSeconds = 0,
    this.pattern = LoadPattern.constant,
    this.endpointType = 'feed',
  });

  /// Total requests across all users.
  int get totalRequests => concurrentUsers * requestsPerUser;

  /// Estimated test duration in milliseconds.
  int get estimatedDurationMs {
    if (durationSeconds > 0) {
      return durationSeconds * 1000;
    }
    // Estimate based on request count and think time
    final requestTimeMs = requestsPerUser * 50; // ~50ms per request
    final totalTimeMs = requestTimeMs + (requestsPerUser * thinkTimeMs);
    return totalTimeMs;
  }

  /// Creates a ramp-up scenario (users join gradually).
  const LoadTestScenario.rampUp({
    required String id,
    required String name,
    required int concurrentUsers,
    int requestsPerUser = 10,
    int thinkTimeMs = 100,
    String endpointType = 'feed',
  }) : this(
          id: id,
          name: name,
          concurrentUsers: concurrentUsers,
          requestsPerUser: requestsPerUser,
          thinkTimeMs: thinkTimeMs,
          pattern: LoadPattern.rampUp,
          endpointType: endpointType,
        );

  /// Creates a spike scenario (sudden burst of users).
  const LoadTestScenario.spike({
    required String id,
    required String name,
    required int concurrentUsers,
    int requestsPerUser = 5,
    int thinkTimeMs = 0,
    String endpointType = 'feed',
  }) : this(
          id: id,
          name: name,
          concurrentUsers: concurrentUsers,
          requestsPerUser: requestsPerUser,
          thinkTimeMs: thinkTimeMs,
          pattern: LoadPattern.spike,
          endpointType: endpointType,
        );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoadTestScenario &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          concurrentUsers == other.concurrentUsers;

  @override
  int get hashCode => Object.hash(id, concurrentUsers);
}

/// Load testing patterns.
enum LoadPattern {
  /// Constant rate of requests.
  constant,

  /// Gradually increase concurrent users.
  rampUp,

  /// Sudden burst of requests.
  spike,

  /// Wave-like pattern (increase then decrease).
  wave,
}

/// Pre-defined scenarios for Civic Commons (Task 12.4).
const List<LoadTestScenario> defaultLoadTestScenarios = [
  LoadTestScenario(
    id: 'feed_baseline',
    name: 'Feed Baseline',
    concurrentUsers: 100,
    requestsPerUser: 20,
    thinkTimeMs: 500,
    endpointType: 'feed',
  ),
  LoadTestScenario(
    id: 'feed_peak',
    name: 'Feed Peak Hours',
    concurrentUsers: 500,
    requestsPerUser: 10,
    thinkTimeMs: 200,
    endpointType: 'feed',
  ),
  LoadTestScenario(
    id: 'search_load',
    name: 'Search Under Load',
    concurrentUsers: 200,
    requestsPerUser: 5,
    thinkTimeMs: 1000,
    endpointType: 'search',
  ),
  LoadTestScenario.rampUp(
    id: 'ramp_to_10k',
    name: 'Ramp to 10,000 Users',
    concurrentUsers: 10000,
    requestsPerUser: 3,
    thinkTimeMs: 2000,
  ),
  LoadTestScenario.spike(
    id: 'viral_spike',
    name: 'Viral Content Spike',
    concurrentUsers: 5000,
    requestsPerUser: 2,
    endpointType: 'post',
  ),
];
