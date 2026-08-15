import 'package:workmanager/workmanager.dart';

/// Configures the `workmanager` plugin for background sync (Task 3.4).
///
/// The callback dispatcher is a top-level entry point registered with
/// `Workmanager().initialize(...)`; it routes the periodic/one-off sync task
/// to the injected [SyncWorker].
///
/// NOTE: `workmanager` requires native platform setup (Android custom
/// Application class / iOS BGTaskScheduler). This package has no `android/`
/// scaffold, so this implementation is compile-verified here; the worker
/// logic itself is fully unit-tested in `lib/sync/domain` + `test/sync/`.
class WorkmanagerScheduler {
  /// Unique name for the periodic sync task (WorkManager dedupes by this).
  static const String periodicSyncUniqueName = 'civic_commons_periodic_sync';

  /// The task name routed to [BackgroundTaskHandler]s.
  static const String syncTaskName = 'civic_commons_sync';

  /// Registers the top-level [callbackDispatcher] (must be a
  /// `@pragma('vm:entry-point')` function) as the WorkManager entry point.
  Future<void> initialize(Future<void> Function() callbackDispatcher) {
    return Workmanager().initialize(callbackDispatcher);
  }

  /// Schedules a repeating sync. [frequency] defaults to 15 minutes.
  Future<void> registerPeriodicSync({
    Duration frequency = const Duration(minutes: 15),
  }) {
    return Workmanager().registerPeriodicTask(
      periodicSyncUniqueName,
      syncTaskName,
      frequency: frequency,
      existingWorkPolicy: ExistingWorkPolicy.keep,
    );
  }

  /// Schedules a one-off sync (e.g. after a reconnection) with an optional
  /// backoff delay for retries.
  Future<void> registerOneOffSync({Duration initialDelay = Duration.zero}) {
    return Workmanager().registerOneOffTask(
      'civic_commons_oneoff_sync',
      syncTaskName,
      initialDelay: initialDelay,
      existingWorkPolicy: ExistingWorkPolicy.replace,
    );
  }

  /// Cancels the periodic sync task.
  Future<void> cancelPeriodicSync() {
    return Workmanager().cancelByUniqueName(periodicSyncUniqueName);
  }
}
