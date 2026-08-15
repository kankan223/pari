import '../domain/conversation.dart';
import '../domain/entity_store.dart';
import '../domain/local_first_repository.dart';
import '../domain/conversation_repository.dart';
import '../domain/sync_conflict_resolver.dart';
import '../domain/sync_queue_item.dart';
import '../domain/sync_queue_repository.dart';
import '../domain/sync_sink.dart';

/// Local-first [ConversationRepository] for Vault data (data layer).
///
/// Same offline-first contract as [LocalMessageRepository]:
/// writes persist to the encrypted local store immediately, then enqueue a
/// [SyncQueueItem]; [fetchLocal] serves the local snapshot with zero network
/// I/O; [sync] drains the queue through the injected [SyncSink].
///
/// SECURITY CHECKPOINT (Task 3.2): no direct HTTP calls — collaborators are
/// only the local [EntityStore] and the injected [SyncSink] port.
class LocalConversationRepository
    implements ConversationRepository, LocalFirstRepository<Conversation> {
  final EntityStore<Conversation> _store;
  final SyncQueueRepository _syncQueue;
  final SyncSink _sink;
  final SyncConflictResolver _conflictResolver;

  const LocalConversationRepository({
    required EntityStore<Conversation> store,
    required SyncQueueRepository syncQueue,
    required SyncSink sink,
    SyncConflictResolver conflictResolver = const SyncConflictResolver(),
  })  : _store = store,
        _syncQueue = syncQueue,
        _sink = sink,
        _conflictResolver = conflictResolver;

  @override
  Future<Conversation> create(Conversation conversation) async {
    await _store.insert(conversation);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: conversation.encryptedSessionState,
    );
    return conversation;
  }

  @override
  Future<Conversation?> getById(String id) => _store.getById(id);

  @override
  Future<List<Conversation>> getAll() => _store.getAll();

  @override
  Future<Conversation> update(Conversation conversation) async {
    await _store.update(conversation);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.update,
      payload: conversation.encryptedSessionState,
    );
    return conversation;
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
      payload: existing.encryptedSessionState,
    );
  }

  @override
  Future<Conversation?> getByParticipantHash(String participantHash) async {
    final all = await _store.getAll();
    for (final c in all) {
      if (c.participantHash == participantHash) {
        return c;
      }
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // LocalFirstRepository
  // -------------------------------------------------------------------------

  @override
  Future<List<Conversation>> fetchLocal() => _store.getAll();

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
