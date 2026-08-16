import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/ledger_vote.dart';
import '../domain/ledger_vote_record.dart';
import '../domain/ledger_vote_sink.dart';
import '../domain/ledger_vote_wire_codec.dart';

/// Production [LedgerVoteSink] (data layer, Task 7.5 Voting System).
///
/// The vote flow's persistence seam, wired the same offline-first way as
/// every other local mutation:
/// 1. The vote record is written to the local [EntityStore] (`post_votes`
///    table inside the SQLCipher-encrypted database) IMMEDIATELY — the UI
///    never waits on the network, and a vote survives a cold restart.
/// 2. A [SyncQueueItem] is enqueued with the serialized vote envelope; the
///    [SyncQueueRepository] seals it with the AES-256-GCM queue cipher
///    BEFORE storage (SECURITY CHECKPOINT Task 3.3/7.5) — the queue never
///    persists plaintext votes.
///
/// The item id doubles as the idempotency key for the sync transport
/// (Idempotency-Key header, Task 5.2/5.3) — a replayed vote push is deduped
/// server-side.
class QueueLedgerVoteSink implements LedgerVoteSink {
  final EntityStore<LedgerVoteRecord> _voteStore;
  final SyncQueueRepository _syncQueue;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  QueueLedgerVoteSink({
    required EntityStore<LedgerVoteRecord> voteStore,
    required SyncQueueRepository syncQueue,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _voteStore = voteStore,
        _syncQueue = syncQueue,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<LedgerVoteRecord>> localVotes() => _voteStore.getAll();

  @override
  Future<String> save(LedgerVote vote) async {
    final id = _idGen.generate();
    // 1. Local-first write — persist immediately inside the encrypted DB.
    await _voteStore.insert(
      LedgerVoteRecord(
        postId: vote.postId,
        direction: vote.direction,
        updatedAt: _clock(),
      ),
    );
    // 2. Queue the mutation — the envelope carries ONLY the public post id
    //    + aggregate direction and is SEALED by the queue repository before
    //    storage. No voter identity ever enters the queue.
    final frame = LedgerVoteWireFrame(
      postId: vote.postId,
      direction: vote.direction,
    );
    await _syncQueue.enqueue(
      operationType: SyncOperationType.update,
      payload: encodeLedgerVoteFrame(frame),
    );
    return id;
  }
}
