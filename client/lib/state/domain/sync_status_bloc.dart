import 'sync_status.dart';

/// BLoC state for sync status.
class SyncStatusState {
  final SyncStatus status;

  /// Number of pending queue items (non-sensitive integer, for UI badges).
  final int pendingCount;

  /// When the last sync run completed (`null` = never synced).
  ///
  /// Non-PII: a UTC timestamp only, rendered by the Task 5.4 status bar's
  /// tap-to-expand panel ("Last synced: …").
  final DateTime? lastSyncAt;

  /// True while a sync run is actively flushing queue items (Task 5.4).
  ///
  /// Drives the subtle progress indicator in the status bar. A pure boolean
  /// derived from queue item states — it never carries payload data.
  final bool isSyncing;

  const SyncStatusState({
    required this.status,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.isSyncing = false,
  });

  SyncStatusState copyWith({
    SyncStatus? status,
    int? pendingCount,
    DateTime? lastSyncAt,
    bool? isSyncing,
  }) =>
      SyncStatusState(
        status: status ?? this.status,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        isSyncing: isSyncing ?? this.isSyncing,
      );
}

/// BLoC (Business Logic Component) for sync status (Task 3.5; UI in 5.4).
///
/// Derives [SyncStatusState] from network state + local queue state:
/// - offline → [SyncStatus.offline]
/// - online with pending queue items → [SyncStatus.queued]
/// - online after a completed sync → [SyncStatus.live]
/// - online while serving from cache → [SyncStatus.cached]
///
/// SECURITY (Task 3.5): state exposes only the enum + an integer count —
/// never payloads, hashes, or decrypted content.
abstract class SyncStatusBloc {
  /// Stream of sync status states.
  Stream<SyncStatusState> get state;

  /// Starts listening to network/queue changes. Must be called once.
  Future<void> start();

  /// Recomputes the status from current network + queue state.
  Future<void> refresh();

  /// Releases resources.
  Future<void> close();
}
