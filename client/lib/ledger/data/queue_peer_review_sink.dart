import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/peer_review.dart';
import '../domain/peer_review_sink.dart';
import '../domain/peer_review_wire_codec.dart';

/// Production [PeerReviewSink] (data layer, Task 7.6 Peer Review Gate).
///
/// The review flow's persistence seam, wired the same offline-first way as
/// every other local mutation:
/// 1. The decision record is written to the local [EntityStore]
///    (`peer_reviews` table inside the SQLCipher-encrypted database)
///    IMMEDIATELY — the UI never waits on the network, and a decision
///    survives a cold restart.
/// 2. A [SyncQueueItem] is enqueued with the serialized review envelope;
///    the [SyncQueueRepository] seals it with the AES-256-GCM queue cipher
///    BEFORE storage (SECURITY CHECKPOINT Task 3.3/7.6) — the queue never
///    persists plaintext review decisions.
///
/// The item id doubles as the idempotency key for the sync transport
/// (Idempotency-Key header, Task 5.2/5.3) — a replayed review push is
/// deduped server-side.
class QueuePeerReviewSink implements PeerReviewSink {
  final EntityStore<PeerReviewRecord> _reviewStore;
  final SyncQueueRepository _syncQueue;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  QueuePeerReviewSink({
    required EntityStore<PeerReviewRecord> reviewStore,
    required SyncQueueRepository syncQueue,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _reviewStore = reviewStore,
        _syncQueue = syncQueue,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<PeerReviewRecord>> localDecisions() => _reviewStore.getAll();

  @override
  Future<String> save(PeerReviewSubmission submission) async {
    final id = _idGen.generate();
    // 1. Local-first write — persist immediately inside the encrypted DB.
    await _reviewStore.insert(
      PeerReviewRecord(
        postId: submission.postId,
        decision: submission.decision,
        reviewedAt: _clock(),
      ),
    );
    // 2. Queue the mutation — the envelope carries ONLY the public post id
    //    + decision code and is SEALED by the queue repository before
    //    storage. No reviewer identity ever enters the queue.
    final frame = PeerReviewWireFrame(
      postId: submission.postId,
      decision: submission.decision,
    );
    await _syncQueue.enqueue(
      operationType: SyncOperationType.update,
      payload: encodePeerReviewFrame(frame),
    );
    return id;
  }
}
