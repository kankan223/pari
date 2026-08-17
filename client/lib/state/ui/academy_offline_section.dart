import 'package:flutter/material.dart';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/academy_video.dart';
import '../../academy/domain/module_asset_manifest.dart';
import '../../academy/domain/offline_module_cache.dart';
import '../../academy/domain/offline_playback.dart';
import '../domain/academy_offline_bloc.dart';
import '../domain/academy_offline_state.dart';
import 'academy_theme.dart';

/// The download-for-offline section (Task 9.4 — Offline Module Caching).
///
/// Renders the module's offline-cache status (NOT DOWNLOADED / PREPARING /
/// READY / FAILED) with the manifest's offline budget, drives the
/// download-for-offline flow with the STORAGE WARNING gate, and reports the
/// deterministic offline-playback decision for the module's video source.
///
/// SECURITY CHECKPOINT (Task 9.4): the section renders ONLY public course
/// content — the module title, sizes (KB/MB), status labels and the
/// playback decision. No full UUID, no identity, no content ever reaches
/// this tree. Every widget consumes state exclusively through the injected
/// [AcademyOfflineBloc] — never the cache repository directly.
class AcademyOfflineSection extends StatefulWidget {
  final AcademyOfflineBloc bloc;
  final AcademyModule module;
  final ModuleAssetManifest manifest;

  /// The module's validated video source (for the offline-playback
  /// decision caption); null = no video for this module.
  final VideoRoomSource? videoSource;

  const AcademyOfflineSection({
    super.key,
    required this.bloc,
    required this.module,
    required this.manifest,
    this.videoSource,
  });

  @override
  State<AcademyOfflineSection> createState() => _AcademyOfflineSectionState();
}

class _AcademyOfflineSectionState extends State<AcademyOfflineSection> {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AcademyOfflineState>(
      stream: widget.bloc.state,
      builder: (context, snapshot) {
        // Late-subscribe fallback (broadcast stream does not replay).
        final state = snapshot.data ?? widget.bloc.current;
        final entry = state.entryFor(widget.module.moduleId);
        final decision = OfflinePlaybackResolver.resolve(
          source: widget.videoSource,
          cache: entry,
        );
        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AcademyTheme.surface,
            border: Border.all(color: AcademyTheme.rule),
            borderRadius: BorderRadius.circular(3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.download_for_offline_rounded,
                      size: 16, color: AcademyTheme.emerald),
                  const SizedBox(width: 8),
                  const Text(
                    'OFFLINE COPY',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                      color: AcademyTheme.ink,
                      fontFamily: AcademyTheme.monoFont,
                    ),
                  ),
                  const Spacer(),
                  _statusChip(
                      entry?.status ?? OfflineCacheStatus.notDownloaded),
                ],
              ),
              const SizedBox(height: 10),
              ..._statusContent(state, entry),
              const SizedBox(height: 8),
              _playbackCaption(decision),
              if (state.storageWarning) ...[
                const SizedBox(height: 10),
                const _StorageWarningBanner(),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(OfflineCacheStatus status) {
    final (label, color) = switch (status) {
      OfflineCacheStatus.downloaded => ('SAVED', AcademyTheme.emerald),
      OfflineCacheStatus.queued || OfflineCacheStatus.downloading => (
          'PREPARING',
          AcademyTheme.muted
        ),
      OfflineCacheStatus.failed => ('FAILED', _alertRed),
      OfflineCacheStatus.notDownloaded => ('OFFLINE', AcademyTheme.muted),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: color,
          fontFamily: AcademyTheme.monoFont,
        ),
      ),
    );
  }

  List<Widget> _statusContent(
      AcademyOfflineState state, ModuleCacheEntry? entry) {
    final sizeLabel =
        AcademyStoragePolicy.formatBytes(widget.manifest.totalSizeBytes);
    switch (entry?.status ?? OfflineCacheStatus.notDownloaded) {
      case OfflineCacheStatus.downloaded:
        return [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: AcademyTheme.emerald),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Offline copy ready · $sizeLabel',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AcademyTheme.ink,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: () =>
                    widget.bloc.removeModuleFromOffline(widget.module.moduleId),
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  'REMOVE',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AcademyTheme.muted,
                    fontFamily: AcademyTheme.monoFont,
                  ),
                ),
              ),
            ],
          ),
        ];
      case OfflineCacheStatus.queued:
      case OfflineCacheStatus.downloading:
        return const [
          Text(
            'Preparing offline copy…',
            style: TextStyle(fontSize: 12, color: AcademyTheme.muted),
          ),
        ];
      case OfflineCacheStatus.failed:
        return [
          const Text(
            'Offline copy failed to download.',
            style: TextStyle(fontSize: 12, color: _alertRed),
          ),
          TextButton(
            onPressed: () => _downloadWithStorageGate(state),
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: const Text(
              'RETRY',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: AcademyTheme.ink,
                fontFamily: AcademyTheme.monoFont,
              ),
            ),
          ),
        ];
      case OfflineCacheStatus.notDownloaded:
        return [
          Text(
            'Not downloaded · $sizeLabel',
            style: const TextStyle(fontSize: 12, color: AcademyTheme.muted),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => _downloadWithStorageGate(state),
              style: FilledButton.styleFrom(
                backgroundColor: AcademyTheme.emerald,
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              icon: const Icon(Icons.download_rounded, size: 16),
              label: const Text(
                'DOWNLOAD FOR OFFLINE',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: AcademyTheme.monoFont,
                ),
              ),
            ),
          ),
        ];
    }
  }

  Widget _playbackCaption(OfflinePlaybackDecision decision) {
    final String caption;
    if (decision.videoAvailableOffline) {
      caption = 'Video and content available offline.';
    } else if (decision.contentAvailableOffline) {
      caption =
          'Content reads offline · video plays online via the privacy embed.';
    } else if (widget.videoSource is YoutubePrivacySource) {
      caption =
          'Video plays online via the privacy embed · download keeps content offline.';
    } else {
      caption = 'No offline copy yet.';
    }
    return Text(
      caption,
      style: const TextStyle(fontSize: 11, color: AcademyTheme.muted),
    );
  }

  /// The storage-warning gate: when this manifest would push the offline
  /// budget over the limit, the user confirms before the download starts.
  Future<void> _downloadWithStorageGate(AcademyOfflineState state) async {
    final wouldExceed = AcademyStoragePolicy.wouldExceed(
      state.totalCachedBytes,
      widget.manifest.totalSizeBytes,
    );
    if (wouldExceed) {
      final sizeLabel =
          AcademyStoragePolicy.formatBytes(widget.manifest.totalSizeBytes);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: AcademyTheme.paper,
          title: const Text(
            'STORAGE WARNING',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFamily: AcademyTheme.monoFont,
              color: AcademyTheme.ink,
            ),
          ),
          content: Text(
            'This download uses $sizeLabel and would exceed the offline '
            'budget. Continue?',
            style: const TextStyle(fontSize: 13, color: AcademyTheme.ink),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCEL',
                  style: TextStyle(fontFamily: AcademyTheme.monoFont)),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: FilledButton.styleFrom(
                backgroundColor: AcademyTheme.emerald,
              ),
              child: const Text('DOWNLOAD',
                  style: TextStyle(fontFamily: AcademyTheme.monoFont)),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return; // storage gate declined — nothing scheduled.
      }
    }
    await widget.bloc.cacheModuleForOffline(
      module: widget.module,
      manifest: widget.manifest,
    );
  }
}

/// Persistent storage warning shown while cached academy content exceeds the
/// offline budget.
class _StorageWarningBanner extends StatelessWidget {
  const _StorageWarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4E0),
        border: Border.all(color: const Color(0xFFE3C48A)),
        borderRadius: BorderRadius.circular(3),
      ),
      child: const Row(
        children: [
          Icon(Icons.storage_rounded, size: 14, color: _alertRed),
          SizedBox(width: 6),
          Expanded(
            child: Text(
              'Offline academy content is over the storage budget — remove '
              'downloads to free space.',
              style: TextStyle(fontSize: 11, color: _alertRed, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// Fixed failure accent (presentation constant — not data).
const Color _alertRed = Color(0xFF9B2C2C);
