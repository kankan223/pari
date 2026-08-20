import 'package:civic_commons/scaling/domain/scaling_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScalingMetrics - Task 12.4', () {
    test('default metrics have zero values', () {
      const metrics = ScalingMetrics();
      expect(metrics.activeConnections, 0);
      expect(metrics.peakConnections, 0);
      expect(metrics.totalRequests, 0);
      expect(metrics.requestsPerSecond, 0);
      expect(metrics.avgLatencyMs, 0);
      expect(metrics.successfulRequests, 0);
      expect(metrics.failedRequests, 0);
    });

    test('copyWith creates new instance', () {
      const original = ScalingMetrics();
      final updated = original.copyWith(
        activeConnections: 100,
        peakConnections: 150,
      );
      expect(updated.activeConnections, 100);
      expect(updated.peakConnections, 150);
      expect(original.activeConnections, 0);
    });

    test('successRate computes correctly', () {
      const metrics = ScalingMetrics(
        totalRequests: 100,
        successfulRequests: 95,
      );
      expect(metrics.successRate, 0.95);
    });

    test('successRate is NaN when no requests', () {
      const metrics = ScalingMetrics();
      expect(metrics.successRate, isNaN);
    });

    test('meetsConcurrencyTarget returns true when >=10000', () {
      const metrics = ScalingMetrics(peakConnections: 10000);
      expect(metrics.meetsConcurrencyTarget, isTrue);
    });

    test('meetsConcurrencyTarget returns false when <10000', () {
      const metrics = ScalingMetrics(peakConnections: 5000);
      expect(metrics.meetsConcurrencyTarget, isFalse);
    });

    test('latencyTargetMet returns true when <200ms', () {
      const metrics = ScalingMetrics(avgLatencyMs: 150);
      expect(metrics.latencyTargetMet, isTrue);
    });

    test('latencyTargetMet returns false when >=200ms', () {
      const metrics = ScalingMetrics(avgLatencyMs: 250);
      expect(metrics.latencyTargetMet, isFalse);
    });

    test('allShardsHealthy returns true when all healthy', () {
      const metrics = ScalingMetrics(healthyShards: 10, totalShards: 10);
      expect(metrics.allShardsHealthy, isTrue);
    });

    test('allShardsHealthy returns false when some unhealthy', () {
      const metrics = ScalingMetrics(healthyShards: 8, totalShards: 10);
      expect(metrics.allShardsHealthy, isFalse);
    });

    test('equality compares key fields', () {
      const a = ScalingMetrics(activeConnections: 100, peakConnections: 150);
      const b = ScalingMetrics(activeConnections: 100, peakConnections: 150);
      const c = ScalingMetrics(activeConnections: 200, peakConnections: 150);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });
}
