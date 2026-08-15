import '../../repository/domain/local_first_repository.dart';

/// Port for the background sync worker (Task 3.4).
///
/// A [SyncWorker] processes pending items from the local sync queue by
/// pushing them through the injected [SyncSink] — the repository layer's ONLY
/// network boundary. It never performs HTTP itself.
///
/// SECURITY CHECKPOINT (Task 3.4): the worker reads ONLY the local encrypted
/// queue and pushes ONLY opaque sealed payloads via [SyncSink]. It respects
/// the offline-first architecture: if there is no connectivity, the
/// reconnection trigger simply does not invoke it.
abstract class SyncWorker {
  /// Drains every pending queue item (in bounded batches), returning the
  /// number pushed vs. failed.
  Future<SyncResult> runOnce();
}
