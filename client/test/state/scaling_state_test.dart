import 'package:civic_commons/scaling/domain/scaling_metrics.dart';
import 'package:civic_commons/state/domain/scaling_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScalingState - Task 12.4', () {
    test('default state has idle phase and zero metrics', () {
      const state = ScalingState();
      expect(state.phase, ScalingPhase.idle);
      expect(state.metrics, const ScalingMetrics());
      expect(state.errorMessage, isNull);
    });

    test('copyWith creates new instance', () {
      const original = ScalingState();
      final updated = original.copyWith(
        phase: ScalingPhase.ready,
        metrics: const ScalingMetrics(peakConnections: 10000),
      );
      expect(updated.phase, ScalingPhase.ready);
      expect(updated.metrics.peakConnections, 10000);
      expect(original.phase, ScalingPhase.idle);
    });

    test('concurrencyTargetMet delegates to metrics', () {
      const met = ScalingState(
        metrics: ScalingMetrics(peakConnections: 10000),
      );
      const notMet = ScalingState(
        metrics: ScalingMetrics(peakConnections: 5000),
      );
      expect(met.concurrencyTargetMet, isTrue);
      expect(notMet.concurrencyTargetMet, isFalse);
    });

    test('latencyTargetMet delegates to metrics', () {
      const met = ScalingState(
        metrics: ScalingMetrics(avgLatencyMs: 100),
      );
      const notMet = ScalingState(
        metrics: ScalingMetrics(avgLatencyMs: 300),
      );
      expect(met.latencyTargetMet, isTrue);
      expect(notMet.latencyTargetMet, isFalse);
    });

    test('allShardsHealthy delegates to metrics', () {
      const met = ScalingState(
        metrics: ScalingMetrics(healthyShards: 10, totalShards: 10),
      );
      const notMet = ScalingState(
        metrics: ScalingMetrics(healthyShards: 8, totalShards: 10),
      );
      expect(met.allShardsHealthy, isTrue);
      expect(notMet.allShardsHealthy, isFalse);
    });

    test('successRatePercent computes correctly', () {
      const state = ScalingState(
        metrics: ScalingMetrics(
          totalRequests: 100,
          successfulRequests: 95,
        ),
      );
      expect(state.successRatePercent, 95.0);
    });

    test('successRatePercent is 0 when no requests', () {
      const state = ScalingState();
      expect(state.successRatePercent, 0);
    });

    test('equality compares phase, metrics, errorMessage', () {
      const a = ScalingState(
        phase: ScalingPhase.ready,
        metrics: ScalingMetrics(peakConnections: 100),
      );
      const b = ScalingState(
        phase: ScalingPhase.ready,
        metrics: ScalingMetrics(peakConnections: 100),
      );
      const c = ScalingState(
        phase: ScalingPhase.error,
        metrics: ScalingMetrics(peakConnections: 100),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('errorMessage is included in copyWith', () {
      const original = ScalingState();
      final withError = original.copyWith(errorMessage: 'Failed');
      expect(withError.errorMessage, 'Failed');
      expect(original.errorMessage, isNull);
    });
  });
}
