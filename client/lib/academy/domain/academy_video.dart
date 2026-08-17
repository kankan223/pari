/// Academy Video Room (Task 9.3 — Privacy-Enhanced Embeds).
///
/// SECURITY CONTRACT (Task 9.3): the Academy video surface NEVER builds a
/// raw player URL from free text. Every embed starts from a STRICTLY
/// validated 11-char YouTube video id ([YouTubeVideoId]) or an OPAQUE
/// manifest reference ([HlsSource]) — never a user-supplied URL. The only
/// URL that can ever be produced is [PrivacyEmbedUrl.forSource], which is
/// hard-coded to YouTube's `youtube-nocookie.com` privacy-enhanced host
/// with `rel=0` (no recommendations), NO autoplay, NO playlist/list param,
/// and NO Shorts surfaces.
///
/// The playback itself is behind the [VideoEmbedLauncher] port so the
/// Academy tree imports NO video SDK (no video_player/chewie/webview) —
/// the privacy boundary holds BY CONSTRUCTION. Production wiring injects a
/// platform launcher at the Phase-9 composition root; the harness and
/// tests use a no-op recorder.
library;

/// Strict YouTube video id validation (RFC-ish 11-char id charset).
///
/// Only `[A-Za-z0-9_-]` of EXACTLY length 11 is accepted. Anything else —
/// including a full URL, an embed path, or a video id with parameters — is
/// rejected. This is the gate that keeps raw URLs out of the embed builder.
abstract final class YouTubeVideoId {
  static final RegExp _pattern = RegExp(r'^[A-Za-z0-9_-]{11}$');

  static bool isValid(String raw) => _pattern.hasMatch(raw);
}

/// A validated video source for the Academy Video Room.
///
/// [YoutubePrivacySource] is the Task 9.3 deliverable (privacy-enhanced
/// embed). [HlsSource] is the proprietary-delivery slot (Bunny.net / R2,
/// TECHSTACK §9.1) — its playback is deferred to the Phase-9 media
/// integration, but the value type + opaque manifest-ref validation land
/// now so the resolver contract is complete.
sealed class VideoRoomSource {
  const VideoRoomSource();
}

/// A curated YouTube lecture, played via privacy-enhanced embed mode.
class YoutubePrivacySource extends VideoRoomSource {
  /// The strictly validated 11-char video id.
  final String videoId;

  // NOTE: not const — the id is validated at construction.
  YoutubePrivacySource({required String videoId})
      : assert(YouTubeVideoId.isValid(videoId),
            'videoId must be an 11-char YouTube id'),
        videoId = videoId;

  /// Validating factory — null when [videoId] is not a valid 11-char id.
  static YoutubePrivacySource? tryParse(String videoId) =>
      YouTubeVideoId.isValid(videoId)
          ? YoutubePrivacySource(videoId: videoId)
          : null;
}

/// A proprietary lecture delivered via HLS (Bunny.net / R2).
///
/// [manifestRef] is OPAQUE and non-PII — never a raw URL, never a
/// filename that could leak identity. Playback lands with the Phase-9
/// media integration; the UI renders a graceful deferred state.
class HlsSource extends VideoRoomSource {
  final String manifestRef;

  const HlsSource({required this.manifestRef});

  static HlsSource? tryParse(String manifestRef) =>
      manifestRef.trim().isNotEmpty
          ? HlsSource(manifestRef: manifestRef)
          : null;
}

/// Builds the ONLY embed URL the Academy may produce.
///
/// Hard-coded to YouTube's privacy-enhanced host:
/// `https://www.youtube-nocookie.com/embed/{video_id}?rel=0&modestbranding=1&controls=1&fs=1`
///
/// SECURITY CHECKPOINT (Task 9.3): the URL is assembled from a validated
/// video id ONLY. No `autoplay`, no `list` (playlist/recommendations), no
/// `shorts`/`si` tracking param is ever emitted — asserted by test. HLS
/// sources return null here (their URL is minted by the production media
/// service in Phase 9).
abstract final class PrivacyEmbedUrl {
  static const String _host = 'https://www.youtube-nocookie.com/embed/';

  /// The privacy-enhanced embed URL for [source], or null when the source
  /// has no client-buildable URL (HLS — deferred to Phase 9).
  static String? forSource(VideoRoomSource source) => switch (source) {
        YoutubePrivacySource(:final videoId) =>
          '$_host$videoId?rel=0&modestbranding=1&controls=1&fs=1',
        HlsSource() => null,
      };
}

/// Resolves a module's OPAQUE content reference to a validated
/// [VideoRoomSource] (port).
///
/// The syllabus carries ONLY opaque non-PII content refs (e.g.
/// `civics/rights-fundamentals/mod-01`) — never URLs. This resolver maps a
/// ref to a curated, validated video source; null means the module has no
/// video yet (the player renders a graceful no-video state).
abstract class VideoRoomSourceResolver {
  VideoRoomSource? resolve(String contentRef);
}

/// Plays (or opens) a validated embed URL (port).
///
/// The Academy tree depends only on this seam — no video SDK import, no
/// webview, no network in the widget tree. Production wiring injects the
/// platform launcher at the Phase-9 composition root.
abstract class VideoEmbedLauncher {
  Future<void> launchEmbed(String url);
}
