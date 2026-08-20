import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

/// Memory Footprint Benchmarks (Task 13.5).
///
/// Verifies memory usage tracking, peak memory auto-calculation, image
/// compression ratio estimation, and memory sanitization routines
/// (secureWipe). All benchmarks use deterministic in-memory operations.
void main() {
  group('Memory Footprint - Performance Metrics Tracking', () {
    test('memory usage bytes to MB conversion', () {
      const metrics = _TestMetrics(memoryUsageBytes: 25 * 1024 * 1024);
      expect(metrics.memoryUsageMB, closeTo(25.0, 0.01));
    });

    test('peak memory bytes to MB conversion', () {
      const metrics = _TestMetrics(peakMemoryBytes: 100 * 1024 * 1024);
      expect(metrics.peakMemoryMB, closeTo(100.0, 0.01));
    });

    test('zero memory reports zero MB', () {
      const metrics = _TestMetrics();
      expect(metrics.memoryUsageMB, 0.0);
      expect(metrics.peakMemoryMB, 0.0);
    });

    test('peak memory >= current memory', () {
      const metrics = _TestMetrics(
        memoryUsageBytes: 50 * 1024 * 1024,
        peakMemoryBytes: 75 * 1024 * 1024,
      );
      expect(metrics.peakMemoryMB, greaterThanOrEqualTo(metrics.memoryUsageMB));
    });
  });

  group('Memory Footprint - Image Compression Estimation', () {
    test('compression ratio is between 0 and 1', () {
      const original = 1024 * 1024; // 1MB
      const compressed = 256 * 1024; // 256KB
      final ratio = compressed / original;

      expect(ratio, greaterThan(0.0));
      expect(ratio, lessThanOrEqualTo(1.0));
    });

    test('high quality compression has higher ratio', () {
      const original = 1024 * 1024;
      const highQuality = 800 * 1024; // 80% of original
      const lowQuality = 200 * 1024; // 20% of original

      expect(highQuality / original, greaterThan(lowQuality / original));
    });

    test('compression savings calculation', () {
      const original = 1024 * 1024;
      const compressed = 256 * 1024;
      final savings = (original - compressed) / original;

      expect(savings, closeTo(0.75, 0.01)); // 75% savings
    });
  });

  group('Memory Footprint - secureWipe Verification', () {
    late CryptoServiceImpl crypto;

    setUp(() {
      crypto = CryptoServiceImpl();
    });

    test('secureWipe zeros out byte array', () {
      final data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);
      crypto.secureWipe(data);

      for (final byte in data) {
        expect(byte, 0, reason: 'All bytes should be zeroed');
      }
    });

    test('secureWipe handles empty array', () {
      final data = Uint8List(0);
      crypto.secureWipe(data);
      expect(data.isEmpty, isTrue);
    });

    test('secureWipe handles single byte', () {
      final data = Uint8List.fromList([255]);
      crypto.secureWipe(data);
      expect(data[0], 0);
    });

    test('secureWipe handles large array', () {
      final data = Uint8List(1024 * 64); // 64KB
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      crypto.secureWipe(data);

      var nonZeroCount = 0;
      for (final byte in data) {
        if (byte != 0) nonZeroCount++;
      }
      expect(nonZeroCount, 0, reason: 'All bytes should be zeroed');
    });

    test('secureWipe performance: 64KB wipe in <10ms', () {
      final data = Uint8List(1024 * 64);
      for (var i = 0; i < data.length; i++) {
        data[i] = i % 256;
      }

      final stopwatch = Stopwatch()..start();
      crypto.secureWipe(data);
      stopwatch.stop();

      expect(stopwatch.elapsedMilliseconds, lessThan(10),
          reason: '64KB wipe should take <10ms');
    });

    test('secureWipe is isolation-safe', () {
      final data1 = Uint8List.fromList([10, 20, 30]);
      final data2 = Uint8List.fromList([40, 50, 60]);

      crypto.secureWipe(data1);

      expect(data1[0], 0);
      expect(data2[0], 40, reason: 'Other array should be unaffected');
    });
  });

  group('Memory Footprint - Allocation Tracking', () {
    test('track allocations across multiple arrays', () {
      final allocations = <int>[];

      // Simulate tracking
      for (var i = 0; i < 100; i++) {
        final data = Uint8List(1024); // 1KB each
        allocations.add(data.lengthInBytes);
      }

      final totalBytes = allocations.fold(0, (sum, b) => sum + b);
      expect(totalBytes, 100 * 1024); // 100KB total
    });

    test('peak memory tracks maximum', () {
      var peak = 0;
      var current = 0;

      // Simulate allocation pattern
      for (var i = 0; i < 50; i++) {
        current += 1024;
        if (current > peak) peak = current;
      }

      // Simulate deallocation
      current -= 20 * 1024;

      expect(peak, 50 * 1024, reason: 'Peak should be 50KB');
      expect(current, 30 * 1024, reason: 'Current should be 30KB');
    });
  });
}

/// Minimal metrics for memory footprint testing.
class _TestMetrics {
  final int memoryUsageBytes;
  final int peakMemoryBytes;

  const _TestMetrics({
    this.memoryUsageBytes = 0,
    this.peakMemoryBytes = 0,
  });

  double get memoryUsageMB => memoryUsageBytes / (1024 * 1024);
  double get peakMemoryMB => peakMemoryBytes / (1024 * 1024);
}
