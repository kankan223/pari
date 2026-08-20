import 'package:civic_commons/cdn/data/in_memory_cdn_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryCdnFetcher - Task 12.3', () {
    late InMemoryCdnFetcher fetcher;

    setUp(() {
      fetcher = InMemoryCdnFetcher();
    });

    test('fetchBytes returns content of expected size', () async {
      final content = await fetcher.fetchBytes(
        'https://example.com/video.mp4',
        expectedSizeBytes: 1024,
      );
      expect(content, hasLength(1024));
    });

    test('fetchBytes tracks TTFB and total bytes', () async {
      fetcher.simulatedTtfbMs = 75;
      await fetcher.fetchBytes(
        'https://example.com/video.mp4',
        expectedSizeBytes: 1024,
      );
      expect(fetcher.lastTtfbMs, 75);
      expect(fetcher.totalBytesDownloaded, 1024);
    });

    test('fetchAndSeal returns sealed content', () async {
      final content = await fetcher.fetchAndSeal(
        'https://example.com/video.mp4',
        expectedSizeBytes: 512,
      );
      expect(content, hasLength(512));
    });

    test('fetchAndSeal tracks metrics', () async {
      fetcher.simulatedTtfbMs = 100;
      await fetcher.fetchAndSeal(
        'https://example.com/video.mp4',
        expectedSizeBytes: 2048,
      );
      expect(fetcher.lastTtfbMs, 100);
      expect(fetcher.totalBytesDownloaded, 2048);
    });

    test('fetchBytes throws on simulated failure', () async {
      fetcher.simulateFailure = true;
      expect(
        () => fetcher.fetchBytes('https://example.com', expectedSizeBytes: 100),
        throwsStateError,
      );
    });

    test('fetchAndSeal throws on simulated failure', () async {
      fetcher.simulateFailure = true;
      expect(
        () =>
            fetcher.fetchAndSeal('https://example.com', expectedSizeBytes: 100),
        throwsStateError,
      );
    });

    test('reset clears all metrics', () async {
      fetcher.simulatedTtfbMs = 100;
      await fetcher.fetchBytes('https://example.com', expectedSizeBytes: 1024);
      fetcher.reset();
      expect(fetcher.lastTtfbMs, 0);
      expect(fetcher.totalBytesDownloaded, 0);
      expect(fetcher.simulateFailure, isFalse);
    });

    test('multiple fetches accumulate total bytes', () async {
      await fetcher.fetchBytes('https://example.com/a', expectedSizeBytes: 500);
      await fetcher.fetchBytes('https://example.com/b', expectedSizeBytes: 300);
      expect(fetcher.totalBytesDownloaded, 800);
    });

    test('failure flag resets after one failure', () async {
      fetcher.simulateFailure = true;
      expect(
        () => fetcher.fetchBytes('https://example.com', expectedSizeBytes: 100),
        throwsStateError,
      );
      // Should succeed on next call
      final content = await fetcher.fetchBytes(
        'https://example.com',
        expectedSizeBytes: 100,
      );
      expect(content, hasLength(100));
    });
  });
}
