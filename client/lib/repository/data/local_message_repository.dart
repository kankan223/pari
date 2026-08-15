import '../domain/entity_store.dart';
import '../domain/local_first_repository.dart';
import '../domain/message.dart';
import '../domain/message_repository.dart';
import '../domain/sync_conflict_resolver.dart';
import '../domain/sync_queue_item.dart';
import '../domain/sync_queue_repository.dart';
import '../domain/sync_sink.dart';

/// Local-first [MessageRepository] (data layer).
///
/// Read/write flow (offline-first):
/// 1. Writes persist to the encrypted local store IMMEDIATELY and return —
///    the UI never waits on the network.
/// 2. Each mutation also enqueues a [SyncQueueItem] (opaque encrypted
///    payload) into the [SyncQueueRepository].
/// 3. [sync] drains pending queue items through the injected [SyncSink] and
///    marks each item success/failed.
///
/// SECURITY CHECKPOINT (Task 3.2): this repository performs NO direct HTTP
/// calls. Its only collaborators are the local [EntityStore] and the
/// injected [SyncSink] port (the sole network boundary).
class LocalMessageRepository
    implements MessageRepository, LocalFirstRepository<Message> {
  final EntityStore<Message> _store;
  final SyncQueueRepository _syncQueue;
  final SyncSink _sink;
  final SyncConflictResolver _conflictResolver;

  const LocalMessageRepository({
    required EntityStore<Message> store,
    required SyncQueueRepository syncQueue,
    required SyncSink sink,
    SyncConflictResolver conflictResolver = const SyncConflictResolver(),
  })  : _store = store,
        _syncQueue = syncQueue,
        _sink = sink,
        _conflictResolver = conflictResolver;

  @override
  Future<Message> create(Message message) async {
    // Local-first write: persist immediately, start undelivered.
    final local = message.copyWith(delivered: false);
    await _store.insert(local);
    // Queue the mutation — payload is the opaque ciphertext, sealed by the
    // queue repository before storage (SECURITY CHECKPOINT 3.3).
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: message.ciphertext,
    );
    return local;
  }

  @override
  Future<Message?> getById(String id) => _store.getById(id);

  @override
  Future<List<Message>> getAll() => _store.getAll();

  @override
  Future<Message> update(Message message) async {
    await _store.update(message);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.update,
      payload: message.ciphertext,
    );
    return message;
  }

  @override
  Future<void> delete(String id) async {
    final existing = await _store.getById(id);
    if (existing == null) {
      return;
    }
    await _store.delete(id);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.delete,
      payload: existing.ciphertext,
    );
  }

  @override
  Future<List<Message>> getByConversation(String conversationId) async {
    final all = await _store.getAll();
    final matches =
        all.where((m) => m.conversationId == conversationId).toList();
    // Oldest first — deterministic ordering for the message thread.
    matches.sort((a, b) => a.id.compareTo(b.id));
    return matches;
  }

  @override
  Future<List<Message>> getUndelivered() async {
    final all = await _store.getAll();
    return all.where((m) => !m.delivered).toList();
  }

  // -------------------------------------------------------------------------
  // LocalFirstRepository
  // -------------------------------------------------------------------------

  @override
  Future<List<Message>> fetchLocal() => _store.getAll();

  @override
  Future<SyncResult> sync() async {
    var pushed = 0;
    var failed = 0;
    var conflicts = 0;
    for (final item in await _syncQueue.getPending()) {
      final outcome = await _sink.push(item);
      final resolution =
          _conflictResolver.resolve(item: item, outcome: outcome);
      switch (resolution.disposition) {
        case SyncDisposition.success:
          await _syncQueue.markSuccess(item.id);
          pushed++;
        case SyncDisposition.retry:
          await _syncQueue.markFailed(item.id);
          failed++;
        case SyncDisposition.superseded:
          await _syncQueue.delete(item.id);
          conflicts++;
      }
    }
    return SyncResult(
      pushed: pushed,
      failed: failed,
      conflicts: conflicts,
    );
  }
}
