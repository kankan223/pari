import 'package:flutter/material.dart';

import '../../academy/domain/academy_video.dart';
import 'academy_theme.dart';

/// The Academy VIDEO ROOM player (Task 9.3 — Privacy-Enhanced Embeds).
///
/// Renders the 16:9 privacy-embed frame for a validated [VideoRoomSource]
/// and plays it through the injected [VideoEmbedLauncher] seam. The embed
/// URL is built ONLY by [PrivacyEmbedUrl.forSource] from a validated video
/// id — `youtube-nocookie.com`, `rel=0`, NO autoplay, NO recommendations,
/// NO Shorts (SECURITY CHECKPOINT 9.3: the widget tree imports no video
/// SDK and cannot construct a raw URL).
///
/// States:
/// - source == null → graceful "no video for this module yet" state.
/// - [HlsSource] → explicit "proprietary HLS lands with Phase 9" state
///   (the URL is minted by the production media service, never client-side).
/// - [YoutubePrivacySource] → the playable privacy-embed frame.
///
/// SECURITY CHECKPOINT (Task 9.3): renders ONLY a validated 11-char video
/// code + fixed labels — zero identity, zero PII, zero telemetry.
class VideoRoomPlayer extends StatefulWidget {
  final VideoRoomSource? source;
  final VideoEmbedLauncher launcher;

  const VideoRoomPlayer({
    super.key,
    required this.source,
    required this.launcher,
  });

  @override
  State<VideoRoomPlayer> createState() => _VideoRoomPlayerState();
}

class _VideoRoomPlayerState extends State<VideoRoomPlayer> {
  bool _launched = false;

  Future<void> _play() async {
    if (_launched) {
      return; // single-launch — no repeat embed spawns.
    }
    final url = PrivacyEmbedUrl.forSource(widget.source!);
    if (url == null) {
      return; // HLS-deferred — nothing to launch yet.
    }
    setState(() => _launched = true);
    await widget.launcher.launchEmbed(url);
  }

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    return Container(
      decoration: BoxDecoration(
        color: AcademyTheme.surface,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.play_circle_outline_rounded,
                    size: 16, color: AcademyTheme.emerald),
                const SizedBox(width: 8),
                const Text(
                  'VIDEO ROOM',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: AcademyTheme.ink,
                    fontFamily: AcademyTheme.monoFont,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: AcademyTheme.emerald.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(2),
                  ),
                  child: const Text(
                    'PRIVACY EMBED',
                    style: TextStyle(
                      fontSize: 9,
                      letterSpacing: 0.6,
                      color: AcademyTheme.emerald,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (source == null)
            const _NoVideoState()
          else if (source is HlsSource)
            const _HlsDeferredState()
          else
            _EmbedFrame(
              videoCode: _shortCode(source as YoutubePrivacySource),
              launched: _launched,
              onPlay: _play,
            ),
        ],
      ),
    );
  }

  /// First 8 chars of the validated video id — a video CODE, never PII.
  static String _shortCode(YoutubePrivacySource source) =>
      source.videoId.length >= 8
          ? source.videoId.substring(0, 8)
          : source.videoId;
}

/// The 16:9 privacy-embed frame: a play control that launches the embed
/// through the injected seam. NO autoplay on build — playback starts only
/// on explicit user tap (SECURITY CHECKPOINT 9.3).
class _EmbedFrame extends StatelessWidget {
  final String videoCode;
  final bool launched;
  final VoidCallback onPlay;

  const _EmbedFrame({
    required this.videoCode,
    required this.launched,
    required this.onPlay,
  });

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        color: const Color(0xFF10141A),
        child: Center(
          child: launched
              ? const Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: AcademyTheme.emerald, size: 28),
                    SizedBox(height: 6),
                    Text(
                      'Opened in privacy-enhanced embed',
                      style: TextStyle(
                        fontSize: 11,
                        color: AcademyTheme.paper,
                        fontFamily: AcademyTheme.monoFont,
                      ),
                    ),
                  ],
                )
              : InkWell(
                  onTap: onPlay,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.play_circle_fill_rounded,
                          color: AcademyTheme.emerald, size: 44),
                      const SizedBox(height: 6),
                      const Text(
                        'PLAY',
                        style: TextStyle(
                          fontSize: 11,
                          letterSpacing: 1.0,
                          color: AcademyTheme.paper,
                          fontFamily: AcademyTheme.monoFont,
                        ),
                      ),
                      Text(
                        videoCode,
                        style: const TextStyle(
                          fontSize: 10,
                          letterSpacing: 0.8,
                          color: AcademyTheme.muted,
                          fontFamily: AcademyTheme.monoFont,
                        ),
                      ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// Graceful state when the module has no video yet.
class _NoVideoState extends StatelessWidget {
  const _NoVideoState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AcademyTheme.paper,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Text(
        'No video for this module yet.',
        style: TextStyle(fontSize: 12, color: AcademyTheme.muted),
      ),
    );
  }
}

/// Explicit deferred state for proprietary HLS content (Bunny.net/R2).
class _HlsDeferredState extends StatelessWidget {
  const _HlsDeferredState();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AcademyTheme.paper,
        border: Border.all(color: AcademyTheme.rule),
        borderRadius: BorderRadius.circular(2),
      ),
      child: const Text(
        'Proprietary lecture playback arrives with the Phase 9 media '
        'delivery.',
        style: TextStyle(fontSize: 12, color: AcademyTheme.muted),
      ),
    );
  }
}
