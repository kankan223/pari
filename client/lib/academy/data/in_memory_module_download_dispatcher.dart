import '../domain/offline_module_cache.dart';

/// In-process [BackgroundDownloadDispatcher] for tests and the harness.
///
/// Mirrors the production WorkManager seam ([WorkmanagerScheduler] pattern):
/// scheduling records the module id and, when [runImmediately] is true,
/// invokes the injected [handler] right away — so a `cacheForOffline` call
/// deterministically drives the download to its terminal state without any
/// platform plugin. The production dispatcher (WorkManager-backed,
/// `lib/sync/data/workmanager_module_download_dispatcher.dart`) is the same
/// port with a compile-verified plugin call.
class InProcessModuleDownloadDispatcher
    implements BackgroundDownloadDispatcher {
  /// Runs the queued download for a module id (composition seam).
  final Future<void> Function(String moduleId) handler;

  /// True = run the handler synchronously on schedule (deterministic tests).
  final bool runImmediately;

  /// Module ids that were scheduled (assertion seam).
  final List<String> scheduled = [];

  InProcessModuleDownloadDispatcher({
    required this.handler,
    this.runImmediately = true,
  });

  @override
  Future<void> scheduleModuleDownload(String moduleId) async {
    scheduled.add(moduleId);
    if (runImmediately) {
      await handler(moduleId);
    }
  }
}
