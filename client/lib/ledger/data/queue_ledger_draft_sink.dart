import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/ledger_draft_record.dart';
import '../domain/ledger_draft_sink.dart';
import '../domain/ledger_post_wire_codec.dart';

/// Production [LedgerDraftSink] (data layer, Task 7.4 Post Creation &
/// Queuing).
///
/// The compose flow's persistence seam, wired the same offline-first way as
/// every other local mutation:
/// 1. The draft is written to the local [EntityStore] (`ledger_drafts`
///    table inside the SQLCipher-encrypted database) IMMEDIATELY — the UI
///    never waits on the network.
/// 2. A [SyncQueueItem] is enqueued with the serialized civic envelope; the
///    [SyncQueueRepository] seals it with the AES-256-GCM queue cipher
///    BEFORE storage (SECURITY CHECKPOINT Task 3.3/7.4) — the queue never
///    persists plaintext post drafts.
///
/// The item id doubles as the idempotency key for the sync transport
/// (Idempotency-Key header, Task 5.2/5.3).
class QueueLedgerDraftSink implements LedgerDraftSink {
  final EntityStore<LedgerDraftRecord> _draftStore;
  final SyncQueueRepository _syncQueue;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  QueueLedgerDraftSink({
    required EntityStore<LedgerDraftRecord> draftStore,
    required SyncQueueRepository syncQueue,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _draftStore = draftStore,
        _syncQueue = syncQueue,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  /// The drafted-but-not-yet-synced rows (local snapshot, offline-first).
  Future<List<LedgerDraftRecord>> localDrafts() => _draftStore.getAll();

  @override
  Future<String> save(LedgerDraft draft) async {
    final id = _idGen.generate();
    // 1. Local-first write — persist immediately inside the encrypted DB.
    await _draftStore.insert(
      LedgerDraftRecord(
        id: id,
        category: draft.category,
        pinCode: draft.pinCode,
        headline: draft.headline,
        body: draft.body,
        createdAt: _clock(),
      ),
    );
    // 2. Queue the mutation — the envelope carries ONLY public civic fields
    //    and is SEALED by the queue repository before storage.
    final frame = LedgerPostWireFrame(
      category: draft.category,
      pinCode: draft.pinCode,
      headline: draft.headline,
      body: draft.body,
    );
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: encodeLedgerPostFrame(frame),
    );
    return id;
  }
}
