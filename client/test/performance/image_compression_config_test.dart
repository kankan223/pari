import 'package:civic_commons/performance/domain/image_compression_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ImageCompressionConfig - Task 12.1', () {
    test('default config has sensible defaults', () {
      const config = ImageCompressionConfig();
      expect(config.quality, 85);
      expect(config.maxWidth, 1920);
      expect(config.maxHeight, 1080);
      expect(config.maintainAspectRatio, true);
      expect(config.stripExif, true);
    });

    test('conservative config reduces quality and dimensions', () {
      const config = ImageCompressionConfig.conservative();
      expect(config.quality, 70);
      expect(config.maxWidth, 1280);
      expect(config.maxHeight, 720);
      expect(config.stripExif, true);
    });

    test('evidence config preserves quality', () {
      const config = ImageCompressionConfig.evidence();
      expect(config.quality, 95);
      expect(config.maxWidth, 2560);
      expect(config.maxHeight, 1440);
      expect(config.stripExif, true); // Even evidence strips EXIF
    });

    test('forTargetSize creates appropriate configs', () {
      final small = ImageCompressionConfig.forTargetSize(30 * 1024);
      expect(small.quality, 50);
      expect(small.maxWidth, 800);

      final medium = ImageCompressionConfig.forTargetSize(100 * 1024);
      expect(medium.quality, 70);
      expect(medium.maxWidth, 1280);

      final large = ImageCompressionConfig.forTargetSize(300 * 1024);
      expect(large.quality, 85);
      expect(large.maxWidth, 1920);

      final xlarge = ImageCompressionConfig.forTargetSize(1000 * 1024);
      expect(xlarge.quality, 95);
      expect(xlarge.maxWidth, 2560);
    });

    test('quality is within valid range', () {
      const configs = [
        ImageCompressionConfig(),
        ImageCompressionConfig.conservative(),
        ImageCompressionConfig.evidence(),
      ];
      for (final config in configs) {
        expect(config.quality, inInclusiveRange(0, 100));
      }
    });

    test('dimensions are non-negative', () {
      const config = ImageCompressionConfig();
      expect(config.maxWidth, greaterThanOrEqualTo(0));
      expect(config.maxHeight, greaterThanOrEqualTo(0));
    });
  });
}
