import 'dart:typed_data';

import '../domain/academy_module.dart';
import '../domain/module_asset_manifest.dart';
import '../domain/module_cache_record.dart';
import '../domain/offline_module_cache.dart';

/// In-memory [OfflineModuleCache] for the harness and widget-test defaults.
///
/// Same semantics as [LocalOfflineModuleCache] (queued → downloading →
/// downloaded/failed, sealed payloads only, idempotent ops) but backed by a
/// plain map — no SQLCipher, no persistence across restarts. The production
/// wiring injects the SQLCipher-backed local cache at the Phase-9
/// composition root.
class InMemoryOfflineModuleCache implements OfflineModuleCache {
  final ModuleDownloader _downloader;
  final BackgroundDownloadDispatcher _dispatcher;
  final Map<String, ModuleCacheRecord> _rows = {};

  InMemoryOfflineModuleCache({
    required ModuleDownloader downloader,
    required BackgroundDownloadDispatcher dispatcher,
  })  : _downloader = downloader,
        _dispatcher = dispatcher;

  @override
  Future<ModuleCacheEntry?> cacheStatusFor(String moduleId) async =>
      _rows[moduleId]?.toEntry();

  @override
  Future<List<ModuleCacheEntry>> allCacheEntries() async =>
      _rows.values.map((r) => r.toEntry()).toList(growable: false);

  @override
  Future<int> totalCachedBytes() async {
    var total = 0;
    for (final r in _rows.values) {
      if (r.status == OfflineCacheStatus.downloaded) {
        total += r.cachedBytes;
      }
    }
    return total;
  }

  @override
  Future<Uint8List?> readCachedContent(String moduleId) async {
    final record = _rows[moduleId];
    if (record == null ||
        record.status != OfflineCacheStatus.downloaded ||
        record.sealedPayload == null) {
      return null;
    }
    return record.sealedPayload;
  }

  @override
  Future<void> cacheForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  }) async {
    final existing = _rows[module.moduleId];
    if (existing != null && existing.status == OfflineCacheStatus.downloaded) {
      return; // already offline — idempotent no-op.
    }
    _rows[module.moduleId] = ModuleCacheRecord(
      moduleId: module.moduleId,
      status: OfflineCacheStatus.queued,
      totalBytes: manifest.totalSizeBytes,
      cachedBytes: 0,
    );
    await _dispatcher.scheduleModuleDownload(module.moduleId);
  }

  @override
  Future<void> removeFromOffline(String moduleId) async {
    _rows.remove(moduleId); // absent row → idempotent no-op.
  }

  /// Runs the queued download (dispatcher task; directly testable).
  Future<void> processQueuedDownload(String moduleId) async {
    final entry = _rows[moduleId];
    if (entry == null || entry.status != OfflineCacheStatus.queued) {
      return;
    }
    _rows[moduleId] = entry.copyWith(status: OfflineCacheStatus.downloading);
    try {
      final sealed =
          await _downloader.downloadModuleContent(moduleId, entry.totalBytes);
      final now = DateTime.now().millisecondsSinceEpoch;
      _rows[moduleId] = entry.copyWith(
        status: OfflineCacheStatus.downloaded,
        cachedBytes: entry.totalBytes,
        downloadedAt: now,
        sealedPayload: sealed,
        cachedAt: now,
      );
    } catch (_) {
      _rows[moduleId] = entry.copyWith(status: OfflineCacheStatus.failed);
    }
  }
}
