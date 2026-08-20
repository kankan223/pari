/// Configuration for HTTP connection pooling (Task 12.4).
///
/// Controls max connections, timeouts, and retry behavior for
/// high-load scenarios. All values are pure integers — no identity, no PII.
class ConnectionPoolConfig {
  /// Maximum number of concurrent connections per host.
  final int maxConnectionsPerHost;

  /// Maximum number of concurrent connections total.
  final int maxConnectionsTotal;

  /// Connection timeout in milliseconds.
  final int connectTimeoutMs;

  /// Request timeout in milliseconds.
  final int requestTimeoutMs;

  /// Idle connection timeout in milliseconds.
  final int idleTimeoutMs;

  /// Maximum number of retries on connection failure.
  final int maxRetries;

  /// Base delay between retries in milliseconds.
  final int retryBaseDelayMs;

  /// Whether to enable HTTP/2 multiplexing.
  final bool enableHttp2;

  /// Whether to enable connection keep-alive.
  final bool enableKeepAlive;

  /// Maximum number of pipelined requests per connection.
  final int maxPipelinedRequests;

  const ConnectionPoolConfig({
    this.maxConnectionsPerHost = 6,
    this.maxConnectionsTotal = 50,
    this.connectTimeoutMs = 5000,
    this.requestTimeoutMs = 30000,
    this.idleTimeoutMs = 60000,
    this.maxRetries = 3,
    this.retryBaseDelayMs = 100,
    this.enableHttp2 = true,
    this.enableKeepAlive = true,
    this.maxPipelinedRequests = 10,
  });

  /// Conservative config for low-end devices.
  const ConnectionPoolConfig.conservative()
      : maxConnectionsPerHost = 2,
        maxConnectionsTotal = 10,
        connectTimeoutMs = 10000,
        requestTimeoutMs = 60000,
        idleTimeoutMs = 30000,
        maxRetries = 5,
        retryBaseDelayMs = 500,
        enableHttp2 = true,
        enableKeepAlive = true,
        maxPipelinedRequests = 5;

  /// Aggressive config for high-end devices.
  const ConnectionPoolConfig.aggressive()
      : maxConnectionsPerHost = 12,
        maxConnectionsTotal = 100,
        connectTimeoutMs = 2000,
        requestTimeoutMs = 15000,
        idleTimeoutMs = 120000,
        maxRetries = 2,
        retryBaseDelayMs = 50,
        enableHttp2 = true,
        enableKeepAlive = true,
        maxPipelinedRequests = 20;

  /// Load test config for 10,000 concurrent users.
  const ConnectionPoolConfig.loadTest()
      : maxConnectionsPerHost = 20,
        maxConnectionsTotal = 200,
        connectTimeoutMs = 3000,
        requestTimeoutMs = 10000,
        idleTimeoutMs = 30000,
        maxRetries = 2,
        retryBaseDelayMs = 100,
        enableHttp2 = true,
        enableKeepAlive = true,
        maxPipelinedRequests = 15;
}
