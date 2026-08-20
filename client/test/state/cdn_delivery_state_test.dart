import 'package:civic_commons/cdn/domain/delivery_metrics.dart';
import 'package:civic_commons/state/domain/cdn_delivery_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CdnDeliveryState - Task 12.3', () {
    test('default state has idle phase and zero metrics', () {
      const state = CdnDeliveryState();
      expect(state.phase, CdnDeliveryPhase.idle);
      expect(state.metrics, const DeliveryMetrics());
      expect(state.errorMessage, isNull);
    });

    test('copyWith creates new instance with updated values', () {
      const original = CdnDeliveryState();
      final updated = original.copyWith(
        phase: CdnDeliveryPhase.ready,
        metrics: const DeliveryMetrics(ttfbMs: 50),
      );
      expect(updated.phase, CdnDeliveryPhase.ready);
      expect(updated.metrics.ttfbMs, 50);
      expect(original.phase, CdnDeliveryPhase.idle);
    });

    test('cacheHitTargetMet delegates to metrics', () {
      const met = CdnDeliveryState(
        metrics: DeliveryMetrics(totalRequests: 20, cacheHits: 17),
      );
      const notMet = CdnDeliveryState(
        metrics: DeliveryMetrics(totalRequests: 20, cacheHits: 15),
      );
      expect(met.cacheHitTargetMet, isTrue);
      expect(notMet.cacheHitTargetMet, isFalse);
    });

    test('totalBytesServed delegates to metrics', () {
      const state = CdnDeliveryState(
        metrics: DeliveryMetrics(bytesDownloaded: 300, bytesFromCache: 700),
      );
      expect(state.totalBytesServed, 1000);
    });

    test('bandwidthSavedPercent computes correctly', () {
      const state = CdnDeliveryState(
        metrics: DeliveryMetrics(bytesDownloaded: 200, bytesFromCache: 800),
      );
      expect(state.bandwidthSavedPercent, 80.0);
    });

    test('bandwidthSavedPercent is 0 when no bytes', () {
      const state = CdnDeliveryState();
      expect(state.bandwidthSavedPercent, 0);
    });

    test('equality compares phase, metrics, and errorMessage', () {
      const a = CdnDeliveryState(
        phase: CdnDeliveryPhase.ready,
        metrics: DeliveryMetrics(ttfbMs: 100),
      );
      const b = CdnDeliveryState(
        phase: CdnDeliveryPhase.ready,
        metrics: DeliveryMetrics(ttfbMs: 100),
      );
      const c = CdnDeliveryState(
        phase: CdnDeliveryPhase.error,
        metrics: DeliveryMetrics(ttfbMs: 100),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('errorMessage is included in copyWith', () {
      const original = CdnDeliveryState();
      final withError = original.copyWith(errorMessage: 'Failed');
      expect(withError.errorMessage, 'Failed');
      expect(original.errorMessage, isNull);
    });
  });
}
