import '../../academy/domain/academy_module.dart';
import '../../academy/domain/module_asset_manifest.dart';
import 'academy_offline_state.dart';

/// BLoC for offline module caching (Task 9.4).
///
/// Loads the local cache snapshot through the [OfflineModuleCache] port and
/// drives the download-for-offline / remove flows. The UI binds to [state]
/// and never touches the cache repository directly.
///
/// SECURITY CHECKPOINT (Task 9.4): state carries only module cache entries
/// (UUID module-id keys + status + sizes) — never content, never identity.
abstract class AcademyOfflineBloc {
  /// Stream of offline-cache states.
  Stream<AcademyOfflineState> get state;

  /// The latest emitted state (non-stream read for navigation wiring).
  AcademyOfflineState get current;

  /// Loads the local cache snapshot.
  Future<void> start();

  /// Retries loading after a failure.
  Future<void> retry();

  /// Queues [module]'s [manifest] for offline download (offline-first).
  Future<void> cacheModuleForOffline({
    required AcademyModule module,
    required ModuleAssetManifest manifest,
  });

  /// Removes [moduleId]'s offline copy.
  Future<void> removeModuleFromOffline(String moduleId);

  /// Releases resources.
  Future<void> close();
}
