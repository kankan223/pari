import 'package:civic_commons/cdn/data/in_memory_cdn_fetcher.dart';
import 'package:civic_commons/cdn/data/in_memory_cdn_repository.dart';
import 'package:civic_commons/cdn/domain/cdn_config.dart';
import 'package:civic_commons/cdn/domain/delivery_metrics.dart';
import 'package:civic_commons/cdn/domain/edge_cache_rule.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — CDN delivery lifecycle integration: configure CDN → resolve
/// presigned URL → fetch asset → verify metrics. Uses the REAL
/// InMemoryCdnRepository + InMemoryCdnFetcher.
void main() {
  group('Task 13.2 — CDN delivery integration', () {
    late InMemoryCdnRepository repo;
    late InMemoryCdnFetcher fetcher;

    setUp(() {
      repo = InMemoryCdnRepository();
      fetcher = InMemoryCdnFetcher();
    });

    test('resolve presigned URL for module asset', () async {
      repo.seedPresignedUrl(
          'module-001/video.mp4', 'https://cdn.example.com/signed-url');

      final url = await repo.resolvePresignedUrl(
        moduleId: 'module-001',
        assetPath: 'video.mp4',
      );

      expect(url, isNotEmpty);
      expect(url, contains('signed-url'));
    });

    test('fetcher returns asset bytes via fetchBytes', () async {
      final bytes = await fetcher.fetchBytes(
        'https://cdn.example.com/asset.bin',
        expectedSizeBytes: 1024,
      );

      expect(bytes, isNotEmpty);
      expect(bytes.length, 1024);
    });

    test('fetcher tracks TTFB and total bytes', () async {
      expect(fetcher.lastTtfbMs, 0);
      expect(fetcher.totalBytesDownloaded, 0);

      await fetcher.fetchBytes(
        'https://cdn.example.com/asset.bin',
        expectedSizeBytes: 2048,
      );
      expect(fetcher.lastTtfbMs, greaterThanOrEqualTo(0));
      expect(fetcher.totalBytesDownloaded, greaterThan(0));
    });

    test('fetcher failure simulation', () async {
      fetcher.simulateFailure = true;

      expect(
        () => fetcher.fetchBytes(
          'https://cdn.example.com/will-fail',
          expectedSizeBytes: 100,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('fetchAndSeal returns sealed content', () async {
      final sealed = await fetcher.fetchAndSeal(
        'https://cdn.example.com/secret.bin',
        expectedSizeBytes: 512,
      );

      expect(sealed, isNotEmpty);
      expect(sealed.length, 512);
      // Sealed content should differ from plain fetch
      final plain = await fetcher.fetchBytes(
        'https://cdn.example.com/plain.bin',
        expectedSizeBytes: 512,
      );
      expect(sealed, isNot(equals(plain)));
    });

    test('CDN config presets have valid values', () {
      const conservative = CdnConfig.conservative();
      expect(conservative.maxConcurrentDownloads, 1);
      expect(conservative.retryCount, 3);

      const aggressive = CdnConfig.aggressive();
      expect(aggressive.maxConcurrentDownloads, 6);
      expect(aggressive.retryCount, 1);

      const defaultConfig = CdnConfig(edgeBaseUrl: '');
      expect(defaultConfig.maxConcurrentDownloads, 3);
      expect(defaultConfig.enableHttp2, isTrue);
    });

    test('edge cache rules have valid TTLs', () {
      final rules = defaultEdgeCacheRules;
      expect(rules, isNotEmpty);

      for (final rule in rules) {
        expect(rule.ttlSeconds, greaterThan(0));
        expect(rule.assetType, isNotEmpty);
        expect(rule.cacheControl, isNotEmpty);
      }
    });

    test('default metrics have zero initial values', () {
      const metrics = DeliveryMetrics();
      expect(metrics.ttfbMs, 0);
      expect(metrics.bytesDownloaded, 0);
      expect(metrics.bytesFromCache, 0);
      expect(metrics.totalRequests, 0);
      expect(metrics.cacheHits, 0);
    });

    test('zero-PII: delivery metrics carry only public counters', () {
      const metrics = DeliveryMetrics(
        ttfbMs: 45,
        bytesDownloaded: 1024 * 1024,
        bytesFromCache: 512 * 1024,
        totalRequests: 100,
        cacheHits: 80,
      );

      final str = metrics.toString().toLowerCase();
      expect(str, isNot(contains('+91')));
      expect(str, isNot(contains('@')));
      expect(str, isNot(contains('phone')));
    });
  });
}
