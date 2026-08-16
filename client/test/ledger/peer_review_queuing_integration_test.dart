import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/data/queue_peer_review_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/ledger/domain/peer_review_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_ledger_review_bloc.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// VERIFY (Task 7.6): integration — a review decision cast offline is
/// recorded locally FIRST (survives a cold restart through the exact row
/// codec), queued as a SEALED envelope, and the sync worker drains it back
/// to the exact review frame bytes with no plaintext ever touching the
/// queue store.
void main() {
  group('Task 7.6 - offline review queuing end-to-end', () {
    test('bloc submit -> local record -> sealed queue -> drained intact',
        () async {
      final cipher = testCipher();
      final post = LedgerPost(
        id: 'p1',
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'H',
        body: 'B',
        authorHandle: 'handle_p1',
        verifiedReviewers: 2,
        status: LedgerPostStatus.peerReview,
        createdAt: DateTime.utc(2026, 8, 10),
      );
      final repo = InMemoryLedgerFeedRepository(seed: [post]);
      final reviewStore =
          InMemoryEntityStore<PeerReviewRecord>((r) => r.postId);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: cipher);
      final reviewSink = QueuePeerReviewSink(
        reviewStore: reviewStore,
        syncQueue: syncQueue,
      );
      final bloc = LocalLedgerReviewBloc(repository: repo, reviews: reviewSink);

      await bloc.start('800001');
      await pumpEventQueue();

      // Cast an approve decision while OFFLINE — the 3rd approval.
      await bloc.submit('p1', PeerReviewDecision.approved);
      await pumpEventQueue();

      // Consensus resolves locally: the post publishes.
      expect((await repo.getById('p1'))!.verifiedReviewers, 3);
      expect((await repo.getById('p1'))!.status, LedgerPostStatus.published);
      // The decision record is persisted locally FIRST.
      expect(await reviewStore.getById('p1'), isNotNull);
      // The queue holds exactly ONE sealed envelope.
      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.update);

      // --- cold restart: rows round-trip through the exact codecs ----------
      final reviewRow =
          peerReviewRecordToRow((await reviewStore.getAll()).single);
      final reviewStoreB =
          InMemoryEntityStore<PeerReviewRecord>((r) => r.postId);
      await reviewStoreB.insert(peerReviewRecordFromRow(reviewRow));
      final queueStoreB = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      await queueStoreB
          .insert(syncQueueItemFromRow(syncQueueItemToRow(queued.single)));

      // The restarted app recovers the local decision.
      final restartedSink = QueuePeerReviewSink(
        reviewStore: reviewStoreB,
        syncQueue: LocalSyncQueueRepository(store: queueStoreB, cipher: cipher),
      );
      final recovered = await restartedSink.localDecisions();
      expect(recovered.single.decision, PeerReviewDecision.approved);

      // --- sync drains the sealed envelope; bytes never changed ------------
      final syncB =
          LocalSyncQueueRepository(store: queueStoreB, cipher: cipher);
      final recording = RecordingSyncSink();
      final worker = BackgroundSyncWorker(queue: syncB, sink: recording);
      final result = await worker.runOnce();
      expect(result.pushed, 1);

      expect(recording.pushed.single.payload, queued.single.payload);
      final frame = decodePeerReviewFrame(
          await cipher.open(recording.pushed.single.payload));
      expect(frame.postId, 'p1');
      expect(frame.decision, PeerReviewDecision.approved);

      await bloc.close();
    });

    test(
        'approve -> reject queues two sealed mutations; consensus only on '
        'the approval', () async {
      final cipher = testCipher();
      final repo = InMemoryLedgerFeedRepository(
        seed: [
          LedgerPost(
            id: 'p1',
            category: LedgerCategory.breakingLocal,
            pinCode: '800001',
            headline: 'H',
            body: 'B',
            authorHandle: 'h',
            verifiedReviewers: 1,
            status: LedgerPostStatus.peerReview,
            createdAt: DateTime.utc(2026, 8, 10),
          ),
        ],
      );
      final reviewStore =
          InMemoryEntityStore<PeerReviewRecord>((r) => r.postId);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: cipher);
      final reviewSink = QueuePeerReviewSink(
        reviewStore: reviewStore,
        syncQueue: syncQueue,
      );
      final bloc = LocalLedgerReviewBloc(repository: repo, reviews: reviewSink);

      await bloc.start('800001');
      await pumpEventQueue();
      await bloc.submit('p1', PeerReviewDecision.approved); // 2/3
      await pumpEventQueue();
      await bloc.submit('p1', PeerReviewDecision.rejected); // no advance
      await pumpEventQueue();

      // Local state: 2/3, still in review.
      expect((await repo.getById('p1'))!.verifiedReviewers, 2);
      expect((await repo.getById('p1'))!.status, LedgerPostStatus.peerReview);
      // Two decisions queued as sealed envelopes.
      final queued = await syncQueue.getAll();
      expect(queued, hasLength(2));
      final decisions = <PeerReviewDecision>[];
      for (final item in queued) {
        decisions.add(
            decodePeerReviewFrame(await cipher.open(item.payload)).decision);
      }
      expect(decisions, [
        PeerReviewDecision.approved,
        PeerReviewDecision.rejected,
      ]);
      await bloc.close();
    });
  });
}
