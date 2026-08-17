import 'package:civic_commons/academy/data/in_memory_video_room_source_resolver.dart';
import 'package:civic_commons/academy/domain/academy_video.dart';
import 'package:civic_commons/state/ui/academy_video_room_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester, {
    VideoRoomSource? source,
    NoopVideoEmbedLauncher? launcher,
  }) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: VideoRoomPlayer(
            source: source,
            launcher: launcher ?? NoopVideoEmbedLauncher(),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  group('VideoRoomPlayer (Task 9.3 — Privacy-Enhanced Embeds)', () {
    testWidgets('renders the VIDEO ROOM header + PRIVACY EMBED badge',
        (tester) async {
      await pumpPlayer(
        tester,
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
      );

      expect(find.text('VIDEO ROOM'), findsOneWidget);
      expect(find.text('PRIVACY EMBED'), findsOneWidget);
      expect(find.text('PLAY'), findsOneWidget);
    });

    testWidgets('SECURITY: NEVER auto-launches on build — play is explicit',
        (tester) async {
      final launcher = NoopVideoEmbedLauncher();
      await pumpPlayer(
        tester,
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
        launcher: launcher,
      );

      // Build + settle without any tap: nothing may have launched.
      expect(launcher.lastLaunched, isNull);
    });

    testWidgets('tapping PLAY launches the exact privacy-enhanced embed URL',
        (tester) async {
      final launcher = NoopVideoEmbedLauncher();
      await pumpPlayer(
        tester,
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
        launcher: launcher,
      );

      await tester.tap(find.text('PLAY'));
      await tester.pump(const Duration(milliseconds: 100));

      expect(
        launcher.lastLaunched,
        'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE'
        '?rel=0&modestbranding=1&controls=1&fs=1',
      );
      // The frame flips to the launched state; the play control (and its
      // InkWell) is replaced, so no further launch can be triggered.
      expect(find.text('Opened in privacy-enhanced embed'), findsOneWidget);
      expect(find.text('PLAY'), findsNothing);
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        launcher.lastLaunched,
        'https://www.youtube-nocookie.com/embed/M7lc1UVf-VE'
        '?rel=0&modestbranding=1&controls=1&fs=1',
        reason: 'single-launch — the embed must never re-spawn',
      );
    });

    testWidgets('renders the graceful no-video state when the source is null',
        (tester) async {
      final launcher = NoopVideoEmbedLauncher();
      await pumpPlayer(tester, source: null, launcher: launcher);

      expect(find.text('No video for this module yet.'), findsOneWidget);
      expect(find.text('PLAY'), findsNothing);
      expect(launcher.lastLaunched, isNull);
    });

    testWidgets(
        'renders the explicit HLS-deferred state for proprietary content',
        (tester) async {
      final launcher = NoopVideoEmbedLauncher();
      await pumpPlayer(
        tester,
        source: const HlsSource(manifestRef: 'civics/lectures/mod-01/hls'),
        launcher: launcher,
      );

      expect(
        find.text('Proprietary lecture playback arrives with the Phase 9 '
            'media delivery.'),
        findsOneWidget,
      );
      expect(find.text('PLAY'), findsNothing);
      expect(launcher.lastLaunched, isNull);
    });

    testWidgets(
        'SECURITY: renders only the 8-char video CODE, never full '
        'ids/PII', (tester) async {
      await pumpPlayer(
        tester,
        source: YoutubePrivacySource(videoId: 'M7lc1UVf-VE'),
      );

      expect(find.text('M7lc1UVf'), findsOneWidget); // 8-char code
      expect(find.text('M7lc1UVf-VE'), findsNothing); // full id never shown
      // No phones, emails, hashes or identity strings on the tree.
      expect(
        find.byWidgetPredicate((w) =>
            w is Text &&
            (RegExp(r'\+?\d{10,15}').hasMatch(w.data ?? '') ||
                RegExp(r'\b[0-9a-f]{64}\b').hasMatch(w.data ?? '') ||
                RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+').hasMatch(w.data ?? ''))),
        findsNothing,
      );
    });

    testWidgets('resolves the module contentRef through the default resolver',
        (tester) async {
      // End-to-end seam: the default InMemory resolver turns the module's
      // opaque content ref into the validated source the player renders.
      final resolver = InMemoryVideoRoomSourceResolver();
      final source = resolver.resolve('civics/rights-fundamentals/mod-01');
      final launcher = NoopVideoEmbedLauncher();
      await pumpPlayer(tester, source: source, launcher: launcher);

      expect(find.text('PLAY'), findsOneWidget);
      await tester.tap(find.text('PLAY'));
      await tester.pump(const Duration(milliseconds: 100));
      expect(launcher.lastLaunched, contains('youtube-nocookie.com'));
    });
  });
}
