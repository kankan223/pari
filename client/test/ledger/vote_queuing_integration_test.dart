import 'package:civic_commons/ledger/data/in_memory_ledger_feed_repository.dart';
import 'package:civic_commons/ledger/data/queue_ledger_vote_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_record.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_ledger_feed_bloc.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// VERIFY (Task 7.5): integration — a vote cast offline is recorded locally
/// FIRST (survives a cold restart through the exact row codec), queued as a
/// SEALED envelope, and the sync worker drains it back to the exact vote
/// frame bytes with no plaintext ever touching the queue store.
void main() {
  group('Task 7.5 - offline vote queuing end-to-end', () {
    test('bloc vote -> local record -> sealed queue -> drained intact',
        () async {
      final cipher = testCipher();
      final post = LedgerPost(
        id: 'p1',
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'H',
        body: 'B',
        authorHandle: 'handle_p1',
        voteCount: 5,
        createdAt: DateTime.utc(2026, 8, 10),
      );
      final repo = InMemoryLedgerFeedRepository(seed: [post]);
      final voteStore = InMemoryEntityStore<LedgerVoteRecord>((r) => r.postId);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: cipher);
      final voteSink = QueueLedgerVoteSink(
        voteStore: voteStore,
        syncQueue: syncQueue,
      );
      final bloc = LocalLedgerFeedBloc(repository: repo, votes: voteSink);

      final states = <dynamic>[];
      final sub = bloc.state.listen(states.add);
      await bloc.start('800001');
      await pumpEventQueue();

      // Cast an upvote while OFFLINE.
      await bloc.vote('p1', LedgerVoteDirection.up);
      await pumpEventQueue();

      // The local post reflects the vote immediately (optimistic).
      expect((await repo.getById('p1'))!.voteCount, 6);
      expect((await repo.getById('p1'))!.myVote, LedgerVoteDirection.up);
      // The vote record is persisted locally FIRST.
      expect(await voteStore.getById('p1'), isNotNull);
      // The queue holds exactly ONE sealed envelope.
      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.update);

      // --- cold restart: rows round-trip through the exact codecs ----------
      final voteRow = ledgerVoteRecordToRow((await voteStore.getAll()).single);
      final voteStoreB = InMemoryEntityStore<LedgerVoteRecord>((r) => r.postId);
      await voteStoreB.insert(ledgerVoteRecordFromRow(voteRow));
      final queueStoreB = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      await queueStoreB
          .insert(syncQueueItemFromRow(syncQueueItemToRow(queued.single)));

      // The restarted app recovers the local vote.
      final restartedSink = QueueLedgerVoteSink(
        voteStore: voteStoreB,
        syncQueue: LocalSyncQueueRepository(store: queueStoreB, cipher: cipher),
      );
      final recovered = await restartedSink.localVotes();
      expect(recovered.single.direction, LedgerVoteDirection.up);

      // --- sync drains the sealed envelope; bytes never changed ------------
      final syncB =
          LocalSyncQueueRepository(store: queueStoreB, cipher: cipher);
      final recording = RecordingSyncSink();
      final worker = BackgroundSyncWorker(queue: syncB, sink: recording);
      final result = await worker.runOnce();
      expect(result.pushed, 1);

      expect(recording.pushed.single.payload, queued.single.payload);
      final frame = decodeLedgerVoteFrame(
          await cipher.open(recording.pushed.single.payload));
      expect(frame.postId, 'p1');
      expect(frame.direction, LedgerVoteDirection.up);

      await sub.cancel();
      await bloc.close();
    });

    test('toggle up -> off -> down queues three sealed mutations', () async {
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
            createdAt: DateTime.utc(2026, 8, 10),
          ),
        ],
      );
      final voteStore = InMemoryEntityStore<LedgerVoteRecord>((r) => r.postId);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: cipher);
      final voteSink = QueueLedgerVoteSink(
        voteStore: voteStore,
        syncQueue: syncQueue,
      );
      final bloc = LocalLedgerFeedBloc(repository: repo, votes: voteSink);

      await bloc.start('800001');
      await pumpEventQueue();
      await bloc.vote('p1', LedgerVoteDirection.up);
      await pumpEventQueue();
      await bloc.vote('p1', LedgerVoteDirection.up); // toggle off
      await pumpEventQueue();
      await bloc.vote('p1', LedgerVoteDirection.down);
      await pumpEventQueue();

      // Local state: final direction is down; count never went negative.
      expect((await repo.getById('p1'))!.myVote, LedgerVoteDirection.down);
      // Every transition is queued (up, none, down) as sealed envelopes.
      final queued = await syncQueue.getAll();
      expect(queued, hasLength(3));
      final directions = <LedgerVoteDirection>[];
      for (final item in queued) {
        directions.add(
            decodeLedgerVoteFrame(await cipher.open(item.payload)).direction);
      }
      expect(directions, [
        LedgerVoteDirection.up,
        LedgerVoteDirection.none,
        LedgerVoteDirection.down
      ]);
      await bloc.close();
    });
  });
}
