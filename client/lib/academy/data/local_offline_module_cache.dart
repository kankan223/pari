import 'dart:typed_data';

import '../../repository/domain/entity_store.dart';
import '../domain/academy_module.dart';
import '../domain/module_asset_manifest.dart';
import '../domain/module_cache_record.dart';
import '../domain/offline_module_cache.dart';

/// Production [OfflineModuleCache] (Task 9.4 — Offline Module Caching).
///
/// Persists cache entries inside the encrypted SQLCipher database
/// (`module_cache` table, schema v11). Written FIRST (offline-first): a
/// `cacheForOffline` call lands the QUEUED row before the background
/// download is scheduled, so the queue intent survives a cold restart —
/// a queued row from a previous run is re-processable by
/// [processQueuedDownload]. The sealed content payload lands in the same
/// row when the download completes.
///
/// SECURITY CHECKPOINT (Task 9.4): keys are validated UUID v4 module ids
/// only; the persisted payload is ALWAYS the AES-256-GCM SEALED ciphertext
/// (the [ModuleDownloader] seals + wipes before returning); the whole file
/// is SQLCipher-encrypted at rest (MASTER_PLAN §9.4 checkpoint: cached
/// content lives in the encrypted partition).
class LocalOfflineModuleCache implements OfflineModuleCache {
  final EntityStore<ModuleCacheRecord> _store;
  final ModuleDownloader _downloader;
  final BackgroundDownloadDispatcher _dispatcher;

  /// Clock seam for deterministic timestamps (defaults to real time).
  final int Function() _nowMs;

  LocalOfflineModuleCache({
    required EntityStore<ModuleCacheRecord> store,
    required ModuleDownloader downloader,
    required BackgroundDownloadDispatcher dispatcher,
    int Function()? nowMs,
  })  : _store = store,
        _downloader = downloader,
        _dispatcher = dispatcher,
        _nowMs = nowMs ?? (() => DateTime.now().millisecondsSinceEpoch);

  @override
  Future<ModuleCacheEntry?> cacheStatusFor(String moduleId) async {
    final record = await _store.getById(moduleId);
    return record?.toEntry();
  }

  @override
  Future<List<ModuleCacheEntry>> allCacheEntries() async {
    final records = await _store.getAll();
    return records.map((r) => r.toEntry()).toList(growable: false);
  }

  @override
  Future<int> totalCachedBytes() async {
    var total = 0;
    for (final r in await _store.getAll()) {
      if (r.status == OfflineCacheStatus.downloaded) {
        total += r.cachedBytes;
      }
    }
    return total;
  }

  @override
  Future<Uint8List?> readCachedContent(String moduleId) async {
    final record = await _store.getById(moduleId);
    if (record == null ||
        record.status != OfflineCacheStatus.downloaded ||
        record.sealedPayload == null) {
      return null; // cache MISS — only ciphertext is ever returned.
    }
    return record.sealedPayload;
  }

  @override
  Future<void> cacheForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  }) async {
    final existing = await _store.getById(module.moduleId);
    if (existing != null && existing.status == OfflineCacheStatus.downloaded) {
      return; // already offline — idempotent no-op.
    }
    // Offline-first: land the QUEUED row, then schedule the background work.
    await _store.insert(ModuleCacheRecord(
      moduleId: module.moduleId,
      status: OfflineCacheStatus.queued,
      totalBytes: manifest.totalSizeBytes,
      cachedBytes: 0,
    ));
    await _dispatcher.scheduleModuleDownload(module.moduleId);
  }

  @override
  Future<void> removeFromOffline(String moduleId) async {
    await _store.delete(moduleId); // absent row → idempotent no-op.
  }

  /// Runs the queued download for [moduleId] (invoked by the background
  /// dispatcher; also directly testable). Reads the persisted QUEUED row
  /// (cold-restart-safe), seals the content, and transitions
  /// queued → downloading → downloaded (or → failed on error).
  Future<void> processQueuedDownload(String moduleId) async {
    final entry = await _store.getById(moduleId);
    if (entry == null || entry.status != OfflineCacheStatus.queued) {
      return; // nothing queued — no-op (idempotent).
    }
    await _store.update(entry.copyWith(status: OfflineCacheStatus.downloading));
    try {
      final sealed =
          await _downloader.downloadModuleContent(moduleId, entry.totalBytes);
      final now = _nowMs();
      await _store.update(entry.copyWith(
        status: OfflineCacheStatus.downloaded,
        cachedBytes: entry.totalBytes,
        downloadedAt: now,
        sealedPayload: sealed,
        cachedAt: now,
      ));
    } catch (_) {
      await _store.update(entry.copyWith(status: OfflineCacheStatus.failed));
    }
  }
}
