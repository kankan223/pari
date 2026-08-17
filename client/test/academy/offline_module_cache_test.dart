import 'package:civic_commons/academy/domain/offline_module_cache.dart';
import 'package:civic_commons/academy/domain/offline_playback.dart';
import 'package:civic_commons/academy/domain/academy_video.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

ModuleCacheEntry _entry(OfflineCacheStatus status) => ModuleCacheEntry(
      moduleId: _m1,
      status: status,
      totalBytes: 1024,
      cachedBytes: status == OfflineCacheStatus.downloaded ? 1024 : 0,
    );

void main() {
  group('AcademyStoragePolicy (Task 9.4 — storage warning)', () {
    test('wouldExceed fires only when the budget would be crossed', () {
      expect(AcademyStoragePolicy.wouldExceed(0, 100, limit: 200), isFalse);
      expect(AcademyStoragePolicy.wouldExceed(100, 100, limit: 200), isFalse);
      // The boundary is inclusive of the limit itself.
      expect(AcademyStoragePolicy.wouldExceed(100, 101, limit: 200), isTrue);
    });

    test('exceeds reports an already-over-budget usage', () {
      expect(AcademyStoragePolicy.exceeds(150, limit: 200), isFalse);
      expect(AcademyStoragePolicy.exceeds(200, limit: 200), isFalse);
      expect(AcademyStoragePolicy.exceeds(201, limit: 200), isTrue);
    });

    test('formatBytes renders KB and MB labels deterministically', () {
      expect(AcademyStoragePolicy.formatBytes(512), '0.5 KB');
      expect(AcademyStoragePolicy.formatBytes(24 * 1024), '24 KB');
      expect(AcademyStoragePolicy.formatBytes(24 * 1024 * 1024), '24 MB');
      expect(AcademyStoragePolicy.formatBytes(200 * 1024 * 1024), '200 MB');
      expect(AcademyStoragePolicy.formatBytes(1500 * 1024 * 1024), '1500 MB');
    });
  });

  group('OfflinePlaybackResolver (Task 9.4 — offline playback logic)', () {
    test(
        'YouTube privacy embed is never video-available offline '
        '(privacy boundary by construction)', () {
      final decision = OfflinePlaybackResolver.resolve(
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
        cache: _entry(OfflineCacheStatus.downloaded),
      );

      expect(decision.contentAvailableOffline, isTrue);
      expect(decision.videoAvailableOffline, isFalse,
          reason: 'the Task 9.3 privacy embed is network-only by design');
    });

    test('HLS source becomes video-available offline once cached', () {
      final decision = OfflinePlaybackResolver.resolve(
        source: const HlsSource(manifestRef: 'academy/hls/mod-01'),
        cache: _entry(OfflineCacheStatus.downloaded),
      );

      expect(decision.contentAvailableOffline, isTrue);
      expect(decision.videoAvailableOffline, isTrue);
    });

    test('uncached module has nothing available offline', () {
      final decision = OfflinePlaybackResolver.resolve(
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
        cache: null,
      );

      expect(decision.contentAvailableOffline, isFalse);
      expect(decision.videoAvailableOffline, isFalse);
    });

    test('failed / queued entries never report offline availability', () {
      for (final status in [
        OfflineCacheStatus.queued,
        OfflineCacheStatus.downloading,
        OfflineCacheStatus.failed,
        OfflineCacheStatus.notDownloaded,
      ]) {
        final decision = OfflinePlaybackResolver.resolve(
          source: const HlsSource(manifestRef: 'academy/hls/mod-01'),
          cache: _entry(status),
        );
        expect(decision.contentAvailableOffline, isFalse,
            reason: '$status must not report offline content');
        expect(decision.videoAvailableOffline, isFalse);
      }
    });

    test('no-video module with cached content reads offline', () {
      final decision = OfflinePlaybackResolver.resolve(
        source: null,
        cache: _entry(OfflineCacheStatus.downloaded),
      );

      expect(decision.contentAvailableOffline, isTrue);
      expect(decision.videoAvailableOffline, isFalse);
    });
  });
}
