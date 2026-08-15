/// Repository interface that returns local data immediately, then syncs
/// (offline-first contract, Task 3.2).
///
/// The UI binds to [fetchLocal]: it returns the locally cached snapshot
/// instantly, without any network I/O, so screens render (LIVE/CACHED) even
/// offline. [sync] then reconciles pending local mutations with the remote
/// through the injected [SyncSink] port.
abstract class LocalFirstRepository<T> {
  /// Returns the locally cached snapshot immediately.
  ///
  /// Guaranteed to perform NO network I/O — it serves only the encrypted
  /// local store. Callers can render this instantly.
  Future<List<T>> fetchLocal();

  /// Pushes pending local mutations to the remote via [SyncSink], then
  /// returns the outcome. Never blocks [fetchLocal].
  Future<SyncResult> sync();
}

/// Outcome of a [LocalFirstRepository.sync] run.
class SyncResult {
  /// Number of queued items the remote acknowledged.
  final int pushed;

  /// Number of queued items the remote rejected (kept for retry).
  final int failed;

  /// Number of queued items DROPPED because a conflict resolved in the
  /// remote's favour (Task 5.5) — the local mutation was superseded by an
  /// authoritative remote version. These are neither pushed nor retried;
  /// the entity state converges from the remote on the next pull.
  final int conflicts;

  const SyncResult({
    required this.pushed,
    required this.failed,
    this.conflicts = 0,
  });

  bool get allSucceeded => failed == 0 && conflicts == 0;
}
