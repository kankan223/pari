import 'academy_video.dart';
import 'offline_module_cache.dart';

/// Offline-playback availability decision (Task 9.4 — offline content
/// playback logic).
///
/// SECURITY CHECKPOINT (Task 9.4): the decision is PURE and deterministic —
/// given the module's validated video source + its cache entry, it reports
/// exactly what is playable without a network. Crucially it NEVER claims
/// offline video for a YouTube privacy embed: those embeds are
/// network-only BY CONSTRUCTION (the privacy boundary of Task 9.3 forbids
/// caching the embed host), so a downloaded module with a YouTube source is
/// content-available-offline but video-unavailable-offline. HLS sources are
/// the offline-playback target once cached (actual HLS rendering lands with
/// the Phase-9 media integration — this is the availability contract).
class OfflinePlaybackDecision {
  /// True when the module's SEALED cached content can be read offline.
  final bool contentAvailableOffline;

  /// True when the module's VIDEO plays without a network.
  final bool videoAvailableOffline;

  const OfflinePlaybackDecision({
    required this.contentAvailableOffline,
    required this.videoAvailableOffline,
  });
}

/// Pure resolver for offline-playback availability.
abstract final class OfflinePlaybackResolver {
  /// Resolves availability for [source] (the module's validated video
  /// source) and [cache] (the module's cache entry — null on a miss).
  static OfflinePlaybackDecision resolve({
    required VideoRoomSource? source,
    required ModuleCacheEntry? cache,
  }) {
    final contentOffline =
        cache != null && cache.status == OfflineCacheStatus.downloaded;
    final videoOffline = contentOffline &&
        switch (source) {
          // A privacy embed is network-only by construction (Task 9.3
          // privacy boundary) — never claim offline video for it.
          YoutubePrivacySource() => false,
          // HLS is the offline-playback target: once cached, it plays
          // offline (rendering lands with the Phase-9 media integration).
          HlsSource() => true,
          null => false,
        };
    return OfflinePlaybackDecision(
      contentAvailableOffline: contentOffline,
      videoAvailableOffline: videoOffline,
    );
  }
}
