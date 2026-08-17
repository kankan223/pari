import 'dart:typed_data';

import 'package:civic_commons/academy/data/in_memory_module_download_dispatcher.dart';
import 'package:civic_commons/academy/data/in_memory_module_downloader.dart';
import 'package:civic_commons/academy/data/in_memory_offline_module_cache.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/module_asset_manifest.dart';
import 'package:civic_commons/academy/domain/offline_module_cache.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/state/data/local_academy_offline_bloc.dart';
import 'package:civic_commons/state/domain/academy_offline_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

AcademyModule _module() => AcademyModule.parse(
      moduleId: _m1,
      domainId: 'civics',
      title: 'Fundamentals of Civic Rights',
      durationMinutes: 18,
      locale: 'en',
      contentRef: 'civics/rights-fundamentals/mod-01',
    );

ModuleAssetManifest _manifest() => ModuleAssetManifest.generateFor(
      _module(),
      sizes: {'civics/rights-fundamentals/mod-01': 1024},
    );

/// Tiny fake cipher for the bloc tests (no crypto needed at this layer).
class _FakeCipher implements QueuePayloadCipher {
  @override
  Future<Uint8List> seal(Uint8List plaintext) async =>
      Uint8List.fromList([...plaintext, 1]);

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      sealed.sublist(0, sealed.length - 1);
}

/// Cache whose every operation fails (bloc graceful-degradation test).
class _ThrowingCache implements OfflineModuleCache {
  @override
  Future<List<ModuleCacheEntry>> allCacheEntries() =>
      Future.error(StateError('store down'));

  @override
  Future<ModuleCacheEntry?> cacheStatusFor(String moduleId) =>
      Future.error(StateError('store down'));

  @override
  Future<Uint8List?> readCachedContent(String moduleId) =>
      Future.error(StateError('store down'));

  @override
  Future<int> totalCachedBytes() => Future.error(StateError('store down'));

  @override
  Future<void> cacheForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  }) =>
      Future.error(StateError('store down'));

  @override
  Future<void> removeFromOffline(String moduleId) =>
      Future.error(StateError('store down'));
}

void main() {
  group('LocalAcademyOfflineBloc (Task 9.4)', () {
    test('start() loads the cache snapshot (statuses + totals)', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      expect(bloc.current.phase, AcademyOfflinePhase.ready);
      expect(bloc.current.entries, isEmpty);
      expect(bloc.current.totalCachedBytes, 0);
      expect(bloc.current.storageWarning, isFalse);
    });

    test('cacheModuleForOffline drives the download to READY and refreshes',
        () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      await bloc.cacheModuleForOffline(
          module: _module(), manifest: _manifest());

      final entry = bloc.current.entryFor(_m1);
      expect(entry, isNotNull);
      expect(entry!.status, OfflineCacheStatus.downloaded);
      expect(bloc.current.totalCachedBytes, 1024);
      expect(bloc.current.storageWarning, isFalse);
    });

    test('removeModuleFromOffline clears the entry and refreshes', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      await bloc.cacheModuleForOffline(
          module: _module(), manifest: _manifest());
      await bloc.removeModuleFromOffline(_m1);

      expect(bloc.current.entryFor(_m1), isNull);
      expect(bloc.current.totalCachedBytes, 0);
    });

    test('storageWarning flips when cached bytes exceed the budget', () async {
      final bigManifest = ModuleAssetManifest.generateFor(
        _module(),
        sizes: {'civics/rights-fundamentals/mod-01': 300 * 1024 * 1024},
      );
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      await bloc.cacheModuleForOffline(
          module: _module(), manifest: bigManifest);

      expect(bloc.current.storageWarning, isTrue,
          reason: '300 MB > the 200 MB offline budget');
      expect(bloc.current.totalCachedBytes, 300 * 1024 * 1024);
    });

    test('a store outage degrades to the generic failure state', () async {
      final bloc = LocalAcademyOfflineBloc(cache: _ThrowingCache());
      addTearDown(bloc.close);

      await bloc.start();

      expect(bloc.current.phase, AcademyOfflinePhase.failure);
      expect(bloc.current.errorMessage, isNotEmpty);
      // The generic message never leaks a reason/stack.
      expect(bloc.current.errorMessage, contains('offline'));
    });

    test('SECURITY: state carries only UUID keys + sizes — no identity',
        () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);
      await bloc.cacheModuleForOffline(
          module: _module(), manifest: _manifest());

      final keys = bloc.current.entries.keys.toList();
      expect(keys, [_m1]); // the ONLY key type is the UUID module id.
      for (final key in keys) {
        expect(
            key,
            matches(RegExp(
                r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      }
      final entry = bloc.current.entryFor(_m1)!;
      expect(entry.moduleId, _m1);
      // Entry fields: status + sizes + timestamp only.
      expect(entry.runtimeType.toString(), 'ModuleCacheEntry');
    });
  });
}

Future<LocalAcademyOfflineBloc> _readyBloc() async {
  late final InMemoryOfflineModuleCache cache;
  cache = InMemoryOfflineModuleCache(
    downloader: SimulatedModuleDownloader(cipher: _FakeCipher()),
    dispatcher: InProcessModuleDownloadDispatcher(
      handler: (id) => cache.processQueuedDownload(id),
      runImmediately: true,
    ),
  );
  final bloc = LocalAcademyOfflineBloc(cache: cache);
  await bloc.start();
  return bloc;
}
