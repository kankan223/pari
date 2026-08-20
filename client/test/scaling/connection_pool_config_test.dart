import 'package:civic_commons/scaling/domain/connection_pool_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConnectionPoolConfig - Task 12.4', () {
    test('default config has sensible defaults', () {
      const config = ConnectionPoolConfig();
      expect(config.maxConnectionsPerHost, 6);
      expect(config.maxConnectionsTotal, 50);
      expect(config.connectTimeoutMs, 5000);
      expect(config.requestTimeoutMs, 30000);
      expect(config.idleTimeoutMs, 60000);
      expect(config.maxRetries, 3);
      expect(config.enableHttp2, isTrue);
      expect(config.enableKeepAlive, isTrue);
    });

    test('conservative config reduces resource usage', () {
      const config = ConnectionPoolConfig.conservative();
      expect(config.maxConnectionsPerHost, 2);
      expect(config.maxConnectionsTotal, 10);
      expect(config.connectTimeoutMs, 10000);
      expect(config.maxRetries, 5);
    });

    test('aggressive config increases resource usage', () {
      const config = ConnectionPoolConfig.aggressive();
      expect(config.maxConnectionsPerHost, 12);
      expect(config.maxConnectionsTotal, 100);
      expect(config.connectTimeoutMs, 2000);
      expect(config.maxRetries, 2);
    });

    test('loadTest config supports high concurrency', () {
      const config = ConnectionPoolConfig.loadTest();
      expect(config.maxConnectionsPerHost, 20);
      expect(config.maxConnectionsTotal, 200);
      expect(config.maxPipelinedRequests, 15);
    });

    test('config values are positive', () {
      const config = ConnectionPoolConfig();
      expect(config.maxConnectionsPerHost, greaterThan(0));
      expect(config.maxConnectionsTotal, greaterThan(0));
      expect(config.connectTimeoutMs, greaterThan(0));
      expect(config.requestTimeoutMs, greaterThan(0));
      expect(config.maxRetries, greaterThanOrEqualTo(0));
    });
  });
}
