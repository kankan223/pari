import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:civic_commons/academy/data/in_memory_module_downloader.dart';
import 'package:civic_commons/academy/data/local_offline_module_cache.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/module_asset_manifest.dart';
import 'package:civic_commons/academy/domain/module_cache_record.dart';
import 'package:civic_commons/academy/domain/offline_module_cache.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';

AcademyModule _module1() => AcademyModule.parse(
      moduleId: _m1,
      domainId: 'civics',
      title: 'Fundamentals of Civic Rights',
      durationMinutes: 18,
      locale: 'en',
      contentRef: 'civics/rights-fundamentals/mod-01',
    );

ModuleAssetManifest _manifest() => ModuleAssetManifest.generateFor(
      _module1(),
      sizes: {'civics/rights-fundamentals/mod-01': 1024},
    );

/// A recording [QueuePayloadCipher] that captures the PLAINTEXT buffer
/// references it receives (for the wipe proof) and returns distinguishable
/// sealed bytes (byte-level proof without Argon2id).
class RecordingCipher implements QueuePayloadCipher {
  final List<Uint8List> sealedInputs = [];

  @override
  Future<Uint8List> seal(Uint8List plaintext) async {
    sealedInputs.add(plaintext);
    // Distinct sealed output — never equal to the plaintext.
    return Uint8List.fromList([...plaintext, 0xAA]);
  }

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      sealed.sublist(0, sealed.length - 1);
}

class FailingDownloader implements ModuleDownloader {
  @override
  Future<Uint8List> downloadModuleContent(String moduleId, int totalBytes) =>
      Future.error(StateError('download failed'));
}

class RecordingDispatcher implements BackgroundDownloadDispatcher {
  final List<String> scheduled = [];

  /// When true, runs [handler] synchronously on schedule (deterministic).
  bool runTasks = false;
  Future<void> Function(String moduleId)? handler;

  @override
  Future<void> scheduleModuleDownload(String moduleId) async {
    scheduled.add(moduleId);
    if (runTasks) {
      await handler!(moduleId);
    }
  }
}

void main() {
  group('LocalOfflineModuleCache (Task 9.4 — offline-first)', () {
    test('cacheForOffline marks QUEUED and schedules the background download',
        () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final dispatcher = RecordingDispatcher();
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: dispatcher,
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());

      final entry = await cache.cacheStatusFor(_m1);
      expect(entry, isNotNull);
      expect(entry!.status, OfflineCacheStatus.queued);
      expect(entry.totalBytes, 1024);
      expect(dispatcher.scheduled, [_m1]);
      // No content yet (miss until the download runs).
      expect(await cache.readCachedContent(_m1), isNull);
    });

    test(
        'processQueuedDownload seals + persists content and transitions to '
        'DOWNLOADED (offline persistence)', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cipher = RecordingCipher();
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: cipher),
        dispatcher: RecordingDispatcher(),
        nowMs: () => 1700000000000,
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);

      final entry = await cache.cacheStatusFor(_m1);
      expect(entry!.status, OfflineCacheStatus.downloaded);
      expect(entry.cachedBytes, 1024);
      expect(entry.downloadedAt, 1700000000000);
      // Cache HIT — the SEALED payload is returned (only ciphertext).
      final sealed = await cache.readCachedContent(_m1);
      expect(sealed, isNotNull);
      expect(sealed!.length, 1025); // plaintext + 0xAA marker
      // Cache MISS for a never-cached module.
      expect(await cache.readCachedContent(_m2), isNull);
    });

    test(
        'BYTE-LEVEL proof: stored sealed bytes never equal the plaintext '
        '(real AES-256-GCM), and the round trip is exact', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cipher = testCipher(); // real fast AES-256-GCM
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: cipher),
        dispatcher: RecordingDispatcher(),
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);

      final sealed = await cache.readCachedContent(_m1);
      // Plaintext is deterministic for the module: a repeated byte pattern
      // sized to the manifest budget.
      final seed = _m1.codeUnits;
      final plaintext = Uint8List(1024);
      for (var i = 0; i < 1024; i++) {
        plaintext[i] = seed[i % seed.length];
      }
      expect(sealed, isNotNull);
      expect(listEquals(sealed, plaintext), isFalse);
      // No 16-byte plaintext window survives in the stored bytes.
      for (var i = 0; i + 16 <= plaintext.length; i++) {
        final window = plaintext.sublist(i, i + 16);
        expect(
          listEquals(sealed!.sublist(i, i + 16), window),
          isFalse,
          reason: 'plaintext windows must not survive at offset $i',
        );
      }
      // Round trip: opening the sealed bytes yields the exact plaintext.
      final opened = await cipher.open(sealed!);
      expect(listEquals(opened, plaintext), isTrue);
    });

    test('MEMORY HYGIENE: the plaintext buffer is zeroed after sealing',
        () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cipher = RecordingCipher();
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: cipher),
        dispatcher: RecordingDispatcher(),
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);

      // The recording cipher holds a REFERENCE to the exact buffer the
      // downloader sealed — after the download completes it must be zeros.
      expect(cipher.sealedInputs, hasLength(1));
      final plaintext = cipher.sealedInputs.single;
      expect(plaintext.every((b) => b == 0), isTrue,
          reason: 'plaintext must be wiped in place after sealing');
    });

    test('a failing download transitions to FAILED and retry recovers',
        () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: FailingDownloader(),
        dispatcher: RecordingDispatcher(),
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);

      expect(
          (await cache.cacheStatusFor(_m1))!.status, OfflineCacheStatus.failed);
      expect(await cache.readCachedContent(_m1), isNull);

      // Retry: a working downloader + a fresh queued cycle recovers.
      final retryCache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      await retryCache.cacheForOffline(
          module: _module1(), manifest: _manifest());
      await retryCache.processQueuedDownload(_m1);

      expect((await retryCache.cacheStatusFor(_m1))!.status,
          OfflineCacheStatus.downloaded);
    });

    test('removeFromOffline clears the row + content (idempotent)', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);
      expect(await cache.cacheStatusFor(_m1), isNotNull);

      await cache.removeFromOffline(_m1);
      expect(await cache.cacheStatusFor(_m1), isNull);
      expect(await cache.readCachedContent(_m1), isNull);
      expect(store.length, 0);

      // Idempotent: removing an absent module is a no-op.
      await cache.removeFromOffline(_m1);
      expect(store.length, 0);
    });

    test('totalCachedBytes counts only downloaded content', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      expect(await cache.totalCachedBytes(), 0);

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);
      expect(await cache.totalCachedBytes(), 1024);

      // A queued-only module contributes nothing.
      final m2 = AcademyModule.parse(
        moduleId: _m2,
        domainId: 'tech',
        title: 'Privacy-First Phone Setup',
        durationMinutes: 15,
        locale: 'en',
        contentRef: 'tech/privacy-phone/mod-03',
      );
      final m2Manifest = ModuleAssetManifest.generateFor(
        m2,
        sizes: {'tech/privacy-phone/mod-03': 2048},
      );
      await cache.cacheForOffline(module: m2, manifest: m2Manifest);
      expect(await cache.totalCachedBytes(), 1024);
    });

    test('cacheForOffline is idempotent for an already-downloaded module',
        () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final dispatcher = RecordingDispatcher()..runTasks = true;
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: dispatcher,
      );
      dispatcher.handler = (id) => cache.processQueuedDownload(id);

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      expect((await cache.cacheStatusFor(_m1))!.status,
          OfflineCacheStatus.downloaded);
      final schedules = dispatcher.scheduled.length;

      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      expect(dispatcher.scheduled.length, schedules,
          reason: 're-downloading a ready module must be a no-op');
    });

    test(
        'COLD RESTART: statuses restore from the same store; a queued row '
        'is re-processable after restart', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      // "Run 1": download completes.
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      await cache.cacheForOffline(module: _module1(), manifest: _manifest());
      await cache.processQueuedDownload(_m1);

      // "Restart": a fresh cache instance over the SAME store (persisted
      // rows) restores the downloaded status + sealed content.
      final restarted = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      final entry = await restarted.cacheStatusFor(_m1);
      expect(entry!.status, OfflineCacheStatus.downloaded);
      expect(await restarted.readCachedContent(_m1), isNotNull);

      // A QUEUED row left by a crashed run is re-processable: mark _m2
      // queued directly in the store (crash mid-flight), then a fresh cache
      // instance picks it up and completes it.
      await store.insert(const ModuleCacheRecord(
        moduleId: _m2,
        status: OfflineCacheStatus.queued,
        totalBytes: 2048,
        cachedBytes: 0,
      ));
      final recovered = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      await recovered.processQueuedDownload(_m2);
      expect((await recovered.cacheStatusFor(_m2))!.status,
          OfflineCacheStatus.downloaded);
      expect((await recovered.cacheStatusFor(_m2))!.cachedBytes, 2048);
    });

    test('processQueuedDownload is a no-op for a non-queued entry', () async {
      final store = InMemoryEntityStore<ModuleCacheRecord>((r) => r.moduleId);
      final cache = LocalOfflineModuleCache(
        store: store,
        downloader: SimulatedModuleDownloader(cipher: RecordingCipher()),
        dispatcher: RecordingDispatcher(),
      );
      // Nothing stored at all.
      await cache.processQueuedDownload(_m1);
      expect(store.length, 0);
    });
  });

  group('module_cache row codec (Task 9.4 — strict bounds)', () {
    test('round-trips a downloaded record including the sealed payload', () {
      final record = ModuleCacheRecord(
        moduleId: _m1,
        status: OfflineCacheStatus.downloaded,
        totalBytes: 1024,
        cachedBytes: 1024,
        downloadedAt: 1700000000000,
        sealedPayload: Uint8List.fromList([1, 2, 3]),
        cachedAt: 1700000000000,
      );

      final row = moduleCacheRecordToRow(record);
      final back = moduleCacheRecordFromRow(row);

      expect(back.moduleId, _m1);
      expect(back.status, OfflineCacheStatus.downloaded);
      expect(back.totalBytes, 1024);
      expect(back.cachedBytes, 1024);
      expect(back.downloadedAt, 1700000000000);
      expect(back.sealedPayload, [1, 2, 3]);
      expect(back.cachedAt, 1700000000000);
    });

    test('read path re-validates: a non-UUID module id throws', () {
      expect(
        () => moduleCacheRecordFromRow({
          'module_id': 'not-a-uuid',
          'status': 'queued',
          'total_bytes': 1,
          'cached_bytes': 0,
        }),
        throwsArgumentError,
      );
    });

    test('read path re-validates: an unknown status throws', () {
      expect(
        () => moduleCacheRecordFromRow({
          'module_id': _m1,
          'status': 'synced',
          'total_bytes': 1,
          'cached_bytes': 0,
        }),
        throwsArgumentError,
      );
    });
  });
}
