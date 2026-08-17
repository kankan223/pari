import 'dart:async';

import '../../academy/domain/academy_module.dart';
import '../../academy/domain/module_asset_manifest.dart';
import '../../academy/domain/offline_module_cache.dart';
import '../domain/academy_offline_bloc.dart';
import '../domain/academy_offline_state.dart';

/// Local [AcademyOfflineBloc] (data layer, Task 9.4).
///
/// Loads the cache snapshot from the local [OfflineModuleCache] port
/// (offline-first — the cache is always local and encrypted) and drives the
/// download/remove flows through it. Cache state is re-read after every
/// mutation so a background download that completes asynchronously is
/// reflected on the next refresh.
class LocalAcademyOfflineBloc implements AcademyOfflineBloc {
  static const String _genericError =
      'Unable to load offline copies. Please try again.';

  final OfflineModuleCache _cache;

  final StreamController<AcademyOfflineState> _controller =
      StreamController<AcademyOfflineState>.broadcast();

  AcademyOfflineState _current = const AcademyOfflineState();

  /// Monotonic sequence — a stale load can never overwrite a fresher one
  /// (codebase convention, cf. [LocalAcademyBloc]).
  int _seq = 0;

  LocalAcademyOfflineBloc({required OfflineModuleCache cache}) : _cache = cache;

  @override
  Stream<AcademyOfflineState> get state => _controller.stream;

  /// The latest emitted state (non-stream read for navigation wiring).
  @override
  AcademyOfflineState get current => _current;

  @override
  Future<void> start() async {
    _current = const AcademyOfflineState(phase: AcademyOfflinePhase.loading);
    _controller.add(_current);
    await _load();
  }

  @override
  Future<void> retry() async {
    _current = _current.copyWith(phase: AcademyOfflinePhase.loading);
    _controller.add(_current);
    await _load();
  }

  Future<void> _load() async {
    final seq = ++_seq;
    try {
      final entries = await _cache.allCacheEntries();
      final total = await _cache.totalCachedBytes();
      if (seq != _seq) {
        return; // stale load — a newer call superseded us.
      }
      _current = AcademyOfflineState(
        phase: AcademyOfflinePhase.ready,
        entries: {for (final e in entries) e.moduleId: e},
        totalCachedBytes: total,
        storageWarning: AcademyStoragePolicy.exceeds(total),
      );
    } catch (_) {
      if (seq != _seq) {
        return;
      }
      _current = _current.copyWith(
        phase: AcademyOfflinePhase.failure,
        errorMessage: _genericError,
      );
    }
    _controller.add(_current);
  }

  @override
  Future<void> cacheModuleForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  }) async {
    // Mutations are best-effort against the LOCAL cache; a failure surfaces
    // as the generic failure state and the previous snapshot stays put
    // (graceful degradation, no crash, no partial state).
    try {
      await _cache.cacheForOffline(module: module, manifest: manifest);
    } catch (_) {
      // Fall through to the refresh — the failure state is emitted there if
      // the cache itself is unreachable; a single failed download surfaces
      // as the module's `failed` status on the next refresh instead.
    }
    await _load();
  }

  @override
  Future<void> removeModuleFromOffline(String moduleId) async {
    try {
      await _cache.removeFromOffline(moduleId);
    } catch (_) {
      // Same graceful-degradation contract as the download path.
    }
    await _load();
  }

  @override
  Future<void> close() => _controller.close();
}
