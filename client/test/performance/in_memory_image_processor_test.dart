import 'dart:typed_data';

import 'package:civic_commons/performance/data/in_memory_image_processor.dart';
import 'package:civic_commons/performance/domain/image_compression_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryImageProcessor - Task 12.1', () {
    late InMemoryImageProcessor processor;

    setUp(() {
      processor = InMemoryImageProcessor();
    });

    test('compress reduces data size proportionally to quality', () async {
      final input = Uint8List(10000);
      final compressed = await processor.compress(
        input,
        config: const ImageCompressionConfig(quality: 50),
      );
      expect(compressed, isNotNull);
      expect(compressed!.length, lessThan(input.length));
    });

    test('compress with default config preserves reasonable size', () async {
      final input = Uint8List(10000);
      final compressed = await processor.compress(input);
      expect(compressed, isNotNull);
      // At quality 85, output should be ~85% of input (with resize)
      expect(compressed!.length, greaterThan(input.length * 0.5));
      expect(compressed.length, lessThan(input.length));
    });

    test('compress returns null for empty input', () async {
      final compressed = await processor.compress(Uint8List(0));
      expect(compressed, isNull);
    });

    test('compress with resize config further reduces size', () async {
      final input = Uint8List(10000);
      final withResize = await processor.compress(
        input,
        config: const ImageCompressionConfig(
          quality: 85,
          maxWidth: 800,
          maxHeight: 600,
        ),
      );
      final withoutResize = await processor.compress(
        input,
        config: const ImageCompressionConfig(
          quality: 85,
          maxWidth: 0,
          maxHeight: 0,
        ),
      );
      expect(withResize, isNotNull);
      expect(withoutResize, isNotNull);
      expect(withResize!.length, lessThanOrEqualTo(withoutResize!.length));
    });

    test('estimateSize returns reasonable estimate', () async {
      final input = Uint8List(10000);
      final estimate = await processor.estimateSize(input);
      // At default quality 85, estimate should be ~85%
      expect(estimate, greaterThan(7000));
      expect(estimate, lessThan(10000));
    });

    test('thumbnail produces smaller output', () async {
      final input = Uint8List(10000);
      final thumb = await processor.thumbnail(input);
      expect(thumb, isNotNull);
      // Thumbnail should be ~10% of original
      expect(thumb!.length, lessThan(input.length * 0.2));
    });

    test('thumbnail returns null for empty input', () async {
      final thumb = await processor.thumbnail(Uint8List(0));
      expect(thumb, isNull);
    });

    test('thumbnail with custom maxDimension', () async {
      final input = Uint8List(10000);
      final thumb = await processor.thumbnail(input, maxDimension: 100);
      expect(thumb, isNotNull);
      expect(thumb!.length, lessThan(input.length));
    });

    test('higher quality produces larger output', () async {
      final input = Uint8List(10000);
      final lowQuality = await processor.compress(
        input,
        config: const ImageCompressionConfig(quality: 30),
      );
      final highQuality = await processor.compress(
        input,
        config: const ImageCompressionConfig(quality: 95),
      );
      expect(lowQuality, isNotNull);
      expect(highQuality, isNotNull);
      expect(lowQuality!.length, lessThan(highQuality!.length));
    });
  });
}
