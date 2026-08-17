import 'package:civic_commons/academy/data/in_memory_video_room_source_resolver.dart';
import 'package:civic_commons/academy/domain/academy_video.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('YouTubeVideoId (Task 9.3)', () {
    test('accepts exactly-11-char ids from the [A-Za-z0-9_-] charset', () {
      expect(YouTubeVideoId.isValid('M7lc1UVf-VE'), isTrue);
      expect(YouTubeVideoId.isValid('dQw4w9WgXcQ'), isTrue);
      expect(YouTubeVideoId.isValid('jNQXAC9IVRw'), isTrue);
    });

    test('rejects wrong lengths', () {
      expect(YouTubeVideoId.isValid(''), isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-V'), isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-VEE'), isFalse);
    });

    test('rejects full URLs, paths and query strings (no raw URLs ever)', () {
      expect(
          YouTubeVideoId.isValid('https://www.youtube.com/watch?v=M7lc1UVf-VE'),
          isFalse);
      expect(
          YouTubeVideoId.isValid('www.youtube-nocookie.com/embed/M7lc1UVf-VE'),
          isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-VE&si=abc'), isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-VE?autoplay=1'), isFalse);
    });

    test('rejects ids with invalid characters', () {
      expect(YouTubeVideoId.isValid('M7lc1UVf-V*'), isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-V '), isFalse);
      expect(YouTubeVideoId.isValid('M7lc1UVf-VE!'), isFalse);
    });
  });

  group('YoutubePrivacySource (Task 9.3)', () {
    test('tryParse accepts a valid 11-char id', () {
      final source = YoutubePrivacySource.tryParse('M7lc1UVf-VE');
      expect(source, isNotNull);
      expect(source!.videoId, 'M7lc1UVf-VE');
    });

    test('tryParse rejects a URL or malformed id (null, no throw)', () {
      expect(YoutubePrivacySource.tryParse('https://youtu.be/dQw4w9WgXcQ'),
          isNull);
      expect(YoutubePrivacySource.tryParse('short'), isNull);
      expect(YoutubePrivacySource.tryParse(''), isNull);
    });

    test('constructor assert rejects a malformed id', () {
      // 12 chars — over the strict 11-char bound, rejected by assert.
      expect(
        () => YoutubePrivacySource(videoId: 'not-a-video!'),
        throwsA(isA<AssertionError>()),
      );
      // 10 chars — under the bound.
      expect(
        () => YoutubePrivacySource(videoId: 'not-video'),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('PrivacyEmbedUrl (Task 9.3 — privacy-enhanced embed builder)', () {
    test('builds the youtube-nocookie.com embed URL for a validated id', () {
      final url = PrivacyEmbedUrl.forSource(
          YoutubePrivacySource(videoId: 'M7lc1UVf-VE'));
      expect(url, isNotNull);
      expect(url, startsWith('https://www.youtube-nocookie.com/embed/'));
      expect(url, contains('M7lc1UVf-VE'));
    });

    test('SECURITY: NO autoplay / list / shorts / si params ever emitted', () {
      final url = PrivacyEmbedUrl.forSource(
          YoutubePrivacySource(videoId: 'M7lc1UVf-VE'))!;
      expect(url.toLowerCase(), isNot(contains('autoplay')));
      expect(url.toLowerCase(), isNot(contains('list=')));
      expect(url.toLowerCase(), isNot(contains('shorts')));
      expect(url.toLowerCase(), isNot(contains('si=')));
      expect(url.toLowerCase(), isNot(contains('start=')));
      expect(url.toLowerCase(), isNot(contains('t=')));
    });

    test('SECURITY: rel=0 (no recommendations) + modest branding present', () {
      final url = PrivacyEmbedUrl.forSource(
          YoutubePrivacySource(videoId: 'M7lc1UVf-VE'))!;
      expect(url, contains('rel=0'));
      expect(url, contains('modestbranding=1'));
      expect(url, contains('controls=1'));
      expect(url, contains('fs=1'));
      // Only the four allowlisted params exist.
      final query = url.split('?').last;
      final params = query.split('&')..sort();
      expect(
        params,
        equals(['controls=1', 'fs=1', 'modestbranding=1', 'rel=0']),
      );
    });

    test('returns null for HLS sources (client cannot mint a signed URL)', () {
      expect(
        PrivacyEmbedUrl.forSource(
            const HlsSource(manifestRef: 'civics/lectures/mod-01/hls')),
        isNull,
      );
    });
  });

  group('InMemoryVideoRoomSourceResolver (Task 9.3)', () {
    test('resolves known opaque refs to validated sources deterministically',
        () {
      final resolver = InMemoryVideoRoomSourceResolver();
      final a = resolver.resolve('civics/rights-fundamentals/mod-01');
      final b = resolver.resolve('civics/rights-fundamentals/mod-01');
      expect(a, isA<YoutubePrivacySource>());
      expect((a as YoutubePrivacySource).videoId,
          (b as YoutubePrivacySource).videoId);
    });

    test('returns null for unknown/empty refs (no-video state)', () {
      final resolver = InMemoryVideoRoomSourceResolver();
      expect(resolver.resolve('tech/privacy-phone/mod-03'), isNull);
      expect(resolver.resolve(''), isNull);
      expect(resolver.resolve('https://example.com/video'), isNull);
    });

    test('SECURITY: the map never holds raw URLs — only 11-char ids', () {
      final resolver = InMemoryVideoRoomSourceResolver();
      // Every resolved source must be a validated YoutubePrivacySource —
      // a URL-shaped ref can never resolve to a playable source.
      const refs = [
        'civics/rights-fundamentals/mod-01',
        'civics/reporting-basics/mod-02',
      ];
      for (final ref in refs) {
        final source = resolver.resolve(ref);
        expect(source, isA<YoutubePrivacySource>(),
            reason: '$ref must resolve to a validated source, never a URL');
      }
    });
  });

  group('NoopVideoEmbedLauncher (Task 9.3)', () {
    test('records the launched URL without opening any network surface',
        () async {
      final launcher = NoopVideoEmbedLauncher();
      const url = 'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE';
      await launcher.launchEmbed(url);
      expect(launcher.lastLaunched, url);
    });
  });
}
