import 'dart:typed_data';

import 'academy_module.dart';
import 'module_asset_manifest.dart';

/// Lifecycle of a module's offline cache entry (Task 9.4).
///
/// Wire names are stable and persisted in the encrypted `module_cache`
/// table (schema v11); the strict decoder rejects unknown values so a
/// corrupted row can never masquerade as a real state.
enum OfflineCacheStatus {
  /// No offline copy exists yet.
  notDownloaded('not_downloaded'),

  /// Download scheduled (background work pending / in flight).
  queued('queued'),

  /// Content currently being fetched + sealed.
  downloading('downloading'),

  /// Content fetched, sealed at rest, and ready for offline use.
  downloaded('downloaded'),

  /// The download failed — the UI offers a retry.
  failed('failed');

  final String wireName;

  const OfflineCacheStatus(this.wireName);

  static OfflineCacheStatus fromWireName(String raw) => values.firstWhere(
        (s) => s.wireName == raw,
        orElse: () => throw ArgumentError('unknown offline cache status: $raw'),
      );
}

/// A module's offline-cache entry (UI-safe projection).
///
/// SECURITY CHECKPOINT (Task 9.4): the entry is keyed by the module's
/// validated UUID v4 id and carries ONLY sizes, a status wire name, and an
/// opaque timestamp — zero identity, zero content.
class ModuleCacheEntry {
  final String moduleId;
  final OfflineCacheStatus status;
  final int totalBytes;
  final int cachedBytes;

  /// Unix-ms timestamp when the download completed (null until then).
  final int? downloadedAt;

  const ModuleCacheEntry({
    required this.moduleId,
    required this.status,
    required this.totalBytes,
    required this.cachedBytes,
    this.downloadedAt,
  });

  bool get isDownloaded => status == OfflineCacheStatus.downloaded;
}

/// Persistence boundary for offline module caching (port).
///
/// The production implementation is backed by the encrypted SQLCipher
/// database (`module_cache` table, schema v11) so cache state survives a
/// cold restart; the harness/tests use an in-memory implementation. Cache
/// keys are ALWAYS validated UUID v4 module ids.
abstract class OfflineModuleCache {
  /// The current cache entry for [moduleId], or null when the module has
  /// never been cached (cache MISS).
  Future<ModuleCacheEntry?> cacheStatusFor(String moduleId);

  /// Every cache entry (local snapshot).
  Future<List<ModuleCacheEntry>> allCacheEntries();

  /// Total bytes of downloaded (ready) content — the offline budget in use.
  Future<int> totalCachedBytes();

  /// Marks [module]'s manifest QUEUED and schedules the background download
  /// through the injected [BackgroundDownloadDispatcher]. Idempotent: an
  /// already-downloaded module is a no-op.
  Future<void> cacheForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  });

  /// Removes the offline copy for [moduleId] (status + sealed content).
  /// Idempotent — removing an absent module is a no-op.
  Future<void> removeFromOffline(String moduleId);

  /// The SEALED cached content for [moduleId] (cache HIT), or null on a
  /// miss. Only ciphertext ever leaves this boundary — the caller opens it
  /// locally (inside the encrypted database) at playback time.
  Future<Uint8List?> readCachedContent(String moduleId);
}

/// Fetches a module's content and returns it SEALED at rest (port).
///
/// The Academy tree imports NO networking — this seam is the ONLY place a
/// download can happen. The production implementation (Phase-9 content
/// delivery: presigned MinIO / R2 / Bunny, TECHSTACK §9.1) seals the
/// fetched content with the AES-256-GCM queue cipher before it ever reaches
/// the cache. The in-process implementation simulates deterministic content
/// and seals it the same way.
abstract class ModuleDownloader {
  /// Downloads [moduleId]'s content (nominal [totalBytes]) and returns the
  /// SEALED payload. Throws on failure (the cache marks the entry failed).
  Future<Uint8List> downloadModuleContent(String moduleId, int totalBytes);
}

/// Schedules a module download to run in the background (port).
///
/// Mirrors [WorkmanagerScheduler] (Task 3.4): the production implementation
/// registers a one-off WorkManager task (compile-verified — the plugin needs
/// native platform setup this repo has no scaffold for); the in-process
/// implementation runs the task handler immediately so tests and the harness
/// stay deterministic and plugin-free.
abstract class BackgroundDownloadDispatcher {
  Future<void> scheduleModuleDownload(String moduleId);
}

/// Pure storage-budget policy for the download-for-offline flow.
///
/// The storage warning fires BEFORE a download when the new manifest would
/// push total cached bytes over the budget, and persists while total usage
/// is over it.
abstract final class AcademyStoragePolicy {
  /// Default offline budget: 200 MB of cached academy content.
  static const int defaultWarnAboveBytes = 200 * 1024 * 1024;

  /// True when adding [additionalBytes] to [currentBytes] exceeds [limit].
  static bool wouldExceed(
    int currentBytes,
    int additionalBytes, {
    int limit = defaultWarnAboveBytes,
  }) =>
      currentBytes + additionalBytes > limit;

  /// True when [currentBytes] already exceeds [limit] (persistent banner).
  static bool exceeds(int currentBytes, {int limit = defaultWarnAboveBytes}) =>
      currentBytes > limit;

  /// Human-readable size label (KB / MB), e.g. `24 MB` — public, non-PII.
  static String formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      final mb = bytes / (1024 * 1024);
      return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
    }
    final kb = bytes / 1024;
    return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
  }
}
