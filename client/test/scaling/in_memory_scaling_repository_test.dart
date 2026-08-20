import 'package:civic_commons/scaling/data/in_memory_scaling_repository.dart';
import 'package:civic_commons/scaling/domain/load_test_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryScalingRepository - Task 12.4', () {
    late InMemoryScalingRepository repo;

    setUp(() {
      repo = InMemoryScalingRepository();
    });

    test('getMetrics returns initial zero metrics', () async {
      final metrics = await repo.getMetrics();
      expect(metrics.activeConnections, 0);
      expect(metrics.totalRequests, 0);
    });

    test('runLoadTest updates metrics and records result', () async {
      const scenario = LoadTestScenario(
        id: 'test',
        name: 'Test',
        concurrentUsers: 100,
        requestsPerUser: 10,
      );
      final metrics = await repo.runLoadTest(scenario);
      expect(metrics.activeConnections, 100);
      expect(metrics.totalRequests, 1000);
      expect(repo.testResults, hasLength(1));
      expect(repo.testResults.first.scenarioId, 'test');
    });

    test('recordRequest updates metrics correctly', () async {
      await repo.recordRequest(
          success: true, latencyMs: 50, shardId: 'shard_11');
      await repo.recordRequest(
          success: false, latencyMs: 100, shardId: 'shard_40');
      final metrics = await repo.getMetrics();
      expect(metrics.totalRequests, 2);
      expect(metrics.successfulRequests, 1);
      expect(metrics.failedRequests, 1);
    });

    test('recordConnection tracks active connections', () async {
      await repo.recordConnection(opened: true);
      await repo.recordConnection(opened: true);
      await repo.recordConnection(opened: false);
      final metrics = await repo.getMetrics();
      expect(metrics.activeConnections, 1);
      expect(metrics.peakConnections, 2);
    });

    test('clearMetrics resets all metrics', () async {
      await repo.recordRequest(success: true, latencyMs: 50, shardId: 's');
      await repo.recordConnection(opened: true);
      await repo.clearMetrics();
      final metrics = await repo.getMetrics();
      expect(metrics.totalRequests, 0);
      expect(metrics.activeConnections, 0);
      expect(repo.testResults, isEmpty);
    });

    test('getConfig returns pool config', () {
      final config = repo.getConfig();
      expect(config.maxConnectionsPerHost, greaterThan(0));
    });

    test('multiple load tests accumulate results', () async {
      const scenario1 =
          LoadTestScenario(id: 't1', name: 'T1', concurrentUsers: 50);
      const scenario2 =
          LoadTestScenario(id: 't2', name: 'T2', concurrentUsers: 100);
      await repo.runLoadTest(scenario1);
      await repo.runLoadTest(scenario2);
      expect(repo.testResults, hasLength(2));
    });
  });

  group('LoadTestResult - Task 12.4', () {
    test('successRate computes correctly', () {
      const result = LoadTestResult(
        scenarioId: 't',
        scenarioName: 'T',
        concurrentUsers: 100,
        totalRequests: 1000,
        successfulRequests: 950,
        failedRequests: 50,
        avgLatencyMs: 50,
        p95LatencyMs: 100,
        p99LatencyMs: 200,
        durationMs: 10000,
      );
      expect(result.successRate, 0.95);
    });

    test('requestsPerSecond computes correctly', () {
      const result = LoadTestResult(
        scenarioId: 't',
        scenarioName: 'T',
        concurrentUsers: 100,
        totalRequests: 1000,
        successfulRequests: 1000,
        failedRequests: 0,
        avgLatencyMs: 50,
        p95LatencyMs: 100,
        p99LatencyMs: 200,
        durationMs: 10000,
      );
      expect(result.requestsPerSecond, 100);
    });
  });
}
