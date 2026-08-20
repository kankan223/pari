import 'package:civic_commons/cdn/domain/cdn_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CdnConfig - Task 12.3', () {
    test('default config has sensible defaults', () {
      const config = CdnConfig(edgeBaseUrl: 'https://cdn.example.com');
      expect(config.presignedUrlLifetimeSeconds, 3600);
      expect(config.maxConcurrentDownloads, 3);
      expect(config.retryCount, 2);
      expect(config.retryBaseDelayMs, 500);
      expect(config.maxDownloadSizeBytes, 200 * 1024 * 1024);
      expect(config.enableHttp2, isTrue);
      expect(config.enableBrotli, isTrue);
      expect(config.downloadTimeoutSeconds, 30);
    });

    test('conservative config reduces resource usage', () {
      const config = CdnConfig.conservative();
      expect(config.presignedUrlLifetimeSeconds, 1800);
      expect(config.maxConcurrentDownloads, 1);
      expect(config.retryCount, 3);
      expect(config.retryBaseDelayMs, 1000);
      expect(config.maxDownloadSizeBytes, 100 * 1024 * 1024);
      expect(config.enableBrotli, isFalse);
      expect(config.downloadTimeoutSeconds, 60);
    });

    test('aggressive config increases resource usage', () {
      const config = CdnConfig.aggressive();
      expect(config.presignedUrlLifetimeSeconds, 7200);
      expect(config.maxConcurrentDownloads, 6);
      expect(config.retryCount, 1);
      expect(config.retryBaseDelayMs, 250);
      expect(config.maxDownloadSizeBytes, 500 * 1024 * 1024);
      expect(config.enableBrotli, isTrue);
      expect(config.downloadTimeoutSeconds, 15);
    });

    test('config values are positive', () {
      const config = CdnConfig(edgeBaseUrl: '');
      expect(config.presignedUrlLifetimeSeconds, greaterThan(0));
      expect(config.maxConcurrentDownloads, greaterThan(0));
      expect(config.retryCount, greaterThanOrEqualTo(0));
      expect(config.maxDownloadSizeBytes, greaterThan(0));
      expect(config.downloadTimeoutSeconds, greaterThan(0));
    });
  });
}
