import 'package:civic_commons/cdn/data/in_memory_cdn_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryCdnRepository - Task 12.3', () {
    late InMemoryCdnRepository repo;

    setUp(() {
      repo = InMemoryCdnRepository();
    });

    test('getMetrics returns initial zero metrics', () async {
      final metrics = await repo.getMetrics();
      expect(metrics.ttfbMs, 0);
      expect(metrics.bytesDownloaded, 0);
    });

    test('resolvePresignedUrl returns seeded URL', () async {
      repo.seedPresignedUrl(
          'mod1/video.mp4', 'https://cdn.example.com/presigned');
      final url = await repo.resolvePresignedUrl(
        moduleId: 'mod1',
        assetPath: 'video.mp4',
      );
      expect(url, 'https://cdn.example.com/presigned');
    });

    test('resolvePresignedUrl throws for unknown key', () async {
      expect(
        () => repo.resolvePresignedUrl(moduleId: 'x', assetPath: 'y'),
        throwsStateError,
      );
    });

    test('downloadAndSeal returns sealed content', () async {
      final content = await repo.downloadAndSeal(
        presignedUrl: 'https://example.com',
        expectedSizeBytes: 100,
      );
      expect(content, hasLength(100));
    });

    test('recordCacheHit updates metrics correctly', () async {
      await repo.recordCacheHit(1024);
      final metrics = await repo.getMetrics();
      expect(metrics.bytesFromCache, 1024);
      expect(metrics.totalRequests, 1);
      expect(metrics.cacheHits, 1);
    });

    test('recordDownload updates metrics correctly', () async {
      await repo.recordDownload(
        bytesDownloaded: 2048,
        ttfbMs: 50,
        downloadTimeMs: 200,
      );
      final metrics = await repo.getMetrics();
      expect(metrics.ttfbMs, 50);
      expect(metrics.bytesDownloaded, 2048);
      expect(metrics.totalRequests, 1);
      expect(metrics.totalDownloadTimeMs, 200);
      expect(metrics.avgDownloadSpeedBps, greaterThan(0));
    });

    test('recordFailure increments failedDownloads', () async {
      await repo.recordFailure();
      final metrics = await repo.getMetrics();
      expect(metrics.failedDownloads, 1);
    });

    test('clearMetrics resets all metrics', () async {
      await repo.recordCacheHit(1024);
      await repo.recordDownload(
        bytesDownloaded: 2048,
        ttfbMs: 50,
        downloadTimeMs: 200,
      );
      await repo.clearMetrics();
      final metrics = await repo.getMetrics();
      expect(metrics.bytesFromCache, 0);
      expect(metrics.bytesDownloaded, 0);
      expect(metrics.totalRequests, 0);
    });

    test('multiple operations accumulate correctly', () async {
      await repo.recordCacheHit(500);
      await repo.recordCacheHit(300);
      await repo.recordDownload(
        bytesDownloaded: 1000,
        ttfbMs: 30,
        downloadTimeMs: 100,
      );
      final metrics = await repo.getMetrics();
      expect(metrics.bytesFromCache, 800);
      expect(metrics.bytesDownloaded, 1000);
      expect(metrics.totalRequests, 3);
      expect(metrics.cacheHits, 2);
    });
  });
}
