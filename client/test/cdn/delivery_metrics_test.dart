import 'package:civic_commons/cdn/domain/delivery_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('DeliveryMetrics - Task 12.3', () {
    test('default metrics have zero values', () {
      const metrics = DeliveryMetrics();
      expect(metrics.ttfbMs, 0);
      expect(metrics.bytesDownloaded, 0);
      expect(metrics.bytesFromCache, 0);
      expect(metrics.totalRequests, 0);
      expect(metrics.cacheHits, 0);
      expect(metrics.failedDownloads, 0);
      expect(metrics.avgDownloadSpeedBps, 0);
      expect(metrics.totalDownloadTimeMs, 0);
    });

    test('copyWith creates new instance with updated values', () {
      const original = DeliveryMetrics();
      final updated = original.copyWith(ttfbMs: 100, bytesDownloaded: 1024);
      expect(updated.ttfbMs, 100);
      expect(updated.bytesDownloaded, 1024);
      expect(original.ttfbMs, 0);
    });

    test('cacheHitRatio computes correctly', () {
      const metrics = DeliveryMetrics(
        totalRequests: 100,
        cacheHits: 85,
      );
      expect(metrics.cacheHitRatio, 0.85);
    });

    test('cacheHitRatio is NaN when no requests', () {
      const metrics = DeliveryMetrics();
      expect(metrics.cacheHitRatio, isNaN);
    });

    test('bandwidthSavedRatio computes correctly', () {
      const metrics = DeliveryMetrics(
        bytesDownloaded: 200,
        bytesFromCache: 800,
      );
      expect(metrics.bandwidthSavedRatio, 0.8);
    });

    test('bandwidthSavedRatio is NaN when no bytes', () {
      const metrics = DeliveryMetrics();
      expect(metrics.bandwidthSavedRatio, isNaN);
    });

    test('totalBytesServed sums downloaded and cached', () {
      const metrics = DeliveryMetrics(
        bytesDownloaded: 300,
        bytesFromCache: 700,
      );
      expect(metrics.totalBytesServed, 1000);
    });

    test('cacheHitTargetMet returns true when ratio >80% with enough requests',
        () {
      const metrics = DeliveryMetrics(
        totalRequests: 20,
        cacheHits: 17,
      );
      expect(metrics.cacheHitTargetMet, isTrue);
    });

    test('cacheHitTargetMet returns false when ratio <=80%', () {
      const metrics = DeliveryMetrics(
        totalRequests: 20,
        cacheHits: 15,
      );
      expect(metrics.cacheHitTargetMet, isFalse);
    });

    test('cacheHitTargetMet returns false with fewer than 10 requests', () {
      const metrics = DeliveryMetrics(
        totalRequests: 5,
        cacheHits: 5,
      );
      expect(metrics.cacheHitTargetMet, isFalse);
    });

    test('equality compares all key fields', () {
      const a = DeliveryMetrics(ttfbMs: 100, bytesDownloaded: 1024);
      const b = DeliveryMetrics(ttfbMs: 100, bytesDownloaded: 1024);
      const c = DeliveryMetrics(ttfbMs: 200, bytesDownloaded: 1024);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent for equal instances', () {
      const a = DeliveryMetrics(ttfbMs: 100);
      const b = DeliveryMetrics(ttfbMs: 100);
      expect(a.hashCode, b.hashCode);
    });
  });
}
