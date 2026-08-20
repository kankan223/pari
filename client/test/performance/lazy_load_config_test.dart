import 'package:civic_commons/performance/domain/lazy_load_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LazyLoadConfig - Task 12.1', () {
    test('default config has sensible defaults', () {
      const config = LazyLoadConfig();
      expect(config.preloadItemCount, 3);
      expect(config.maxConcurrentLoads, 4);
      expect(config.viewportThresholdPx, 200.0);
      expect(config.maxImageCacheBytes, 50 * 1024 * 1024);
      expect(config.maxImageCacheCount, 100);
    });

    test('conservative config reduces resource usage', () {
      const config = LazyLoadConfig.conservative();
      expect(config.preloadItemCount, 1);
      expect(config.maxConcurrentLoads, 2);
      expect(config.viewportThresholdPx, 100.0);
      expect(config.maxImageCacheBytes, 20 * 1024 * 1024);
      expect(config.maxImageCacheCount, 50);
    });

    test('aggressive config increases resource usage', () {
      const config = LazyLoadConfig.aggressive();
      expect(config.preloadItemCount, 5);
      expect(config.maxConcurrentLoads, 8);
      expect(config.viewportThresholdPx, 400.0);
      expect(config.maxImageCacheBytes, 100 * 1024 * 1024);
      expect(config.maxImageCacheCount, 200);
    });

    test('config values are positive', () {
      const config = LazyLoadConfig();
      expect(config.preloadItemCount, greaterThan(0));
      expect(config.maxConcurrentLoads, greaterThan(0));
      expect(config.viewportThresholdPx, greaterThan(0));
      expect(config.maxImageCacheBytes, greaterThan(0));
      expect(config.maxImageCacheCount, greaterThan(0));
    });

    test('conservative is smaller than default', () {
      const conservative = LazyLoadConfig.conservative();
      const default_ = LazyLoadConfig();
      expect(
          conservative.preloadItemCount, lessThan(default_.preloadItemCount));
      expect(conservative.maxConcurrentLoads,
          lessThan(default_.maxConcurrentLoads));
      expect(conservative.maxImageCacheBytes,
          lessThan(default_.maxImageCacheBytes));
    });

    test('default is smaller than aggressive', () {
      const default_ = LazyLoadConfig();
      const aggressive = LazyLoadConfig.aggressive();
      expect(default_.preloadItemCount, lessThan(aggressive.preloadItemCount));
      expect(
          default_.maxConcurrentLoads, lessThan(aggressive.maxConcurrentLoads));
      expect(
          default_.maxImageCacheBytes, lessThan(aggressive.maxImageCacheBytes));
    });
  });
}
