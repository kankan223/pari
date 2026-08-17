import 'package:workmanager/workmanager.dart';

import '../../academy/domain/offline_module_cache.dart';

/// Production [BackgroundDownloadDispatcher] backed by the `workmanager`
/// plugin (Task 9.4 — Offline Module Caching).
///
/// Mirrors [WorkmanagerScheduler] (Task 3.4): the plugin call is the seam,
/// and the actual download logic lives in [LocalOfflineModuleCache]
/// (`processQueuedDownload` — fully unit-tested). On device, the scheduled
/// background task reconstructs the cache from the encrypted database and
/// runs the queued download; the Academy tree itself never imports the
/// plugin (this file lives in `lib/sync/data` next to the other WorkManager
/// wiring).
///
/// NOTE: `workmanager` requires native platform setup (Android custom
/// Application class / iOS BGTaskScheduler). This repo has no `android/`
/// scaffold, so this implementation is compile-verified here; the worker
/// logic is unit-tested in `test/academy/`.
class WorkmanagerModuleDownloadDispatcher
    implements BackgroundDownloadDispatcher {
  /// The task name routed to the download background handler.
  static const String downloadTaskName = 'civic_commons_module_download';

  @override
  Future<void> scheduleModuleDownload(String moduleId) {
    // One-off per module id — WorkManager dedupes by unique name.
    return Workmanager().registerOneOffTask(
      'civic_commons_download_$moduleId',
      downloadTaskName,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }
}
