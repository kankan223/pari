import '../domain/academy_video.dart';

/// Deterministic in-memory [VideoRoomSourceResolver] (Task 9.3).
///
/// Maps the seed syllabus' OPAQUE content refs to curated, validated
/// YouTube video ids. Deterministic — the same ref always resolves to the
/// same source; unknown/empty refs resolve to null (no video yet).
///
/// SECURITY CHECKPOINT (Task 9.3): this resolver ONLY accepts the fixed
/// opaque refs below and returns STRICTLY validated 11-char video ids —
/// no free-text URLs, no tracking params, no identity can enter the map.
/// The production resolver will map refs through the Academy Service
/// (TECHSTACK §9.1) which returns the same validated shape.
class InMemoryVideoRoomSourceResolver implements VideoRoomSourceResolver {
  /// Opaque content ref → curated public-domain demo video id.
  static const Map<String, String> _refToVideoId = {
    'civics/rights-fundamentals/mod-01': 'M7lc1UVf-VE',
    'civics/reporting-basics/mod-02': 'M7lc1UVf-VE',
  };

  @override
  VideoRoomSource? resolve(String contentRef) {
    final videoId = _refToVideoId[contentRef];
    if (videoId == null) {
      return null; // unknown ref — no video for this module yet.
    }
    return YoutubePrivacySource.tryParse(videoId);
  }
}

/// No-op [VideoEmbedLauncher] for the harness and tests.
///
/// The harness must never open a real network surface — the embed URL is
/// produced (so tests can assert it), but nothing is launched. Production
/// wiring injects the real platform launcher at the Phase-9 composition
/// root.
class NoopVideoEmbedLauncher implements VideoEmbedLauncher {
  /// The last URL that would have been launched (test assertion seam).
  String? lastLaunched;

  @override
  Future<void> launchEmbed(String url) async {
    lastLaunched = url;
  }
}
