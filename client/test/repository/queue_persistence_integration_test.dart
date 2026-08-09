import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';

import 'fakes.dart';

/// VERIFY (Task 5.6): integration — the offline mutation queue survives a
/// cold app restart through the EXACT SQLCipher row boundary, and a run
/// interrupted mid-sync (crash, battery pull, OS kill) is recovered and
/// drained with byte-identical sealed payloads.
///
/// The real `SqliteEntityStore` needs the native SQLCipher library, so per
/// repo convention the restart is simulated at the exact serialization
/// boundary it uses: rows are written with [syncQueueItemToRow] (what a
/// process-1 insert produces), then read back with [syncQueueItemFromRow]
/// (what a process-2 `getAll()` decodes). Everything in between — queue
/// states, ordering, sealed payloads — is the real production code path.
void main() {
  group('Task 5.6 - queue persistence across cold restart', () {
    test(
        'restart round-trips every state; recovery + drain deliver the '
        'original payloads', () async {
      final cipher = testCipher();
      var now = DateTime(2026, 8, 1, 12);

      // --- process 1: enqueue, then crash mid-drain ------------------------
      final storeA = queueStore();
      final repoA = LocalSyncQueueRepository(
        store: storeA,
        cipher: cipher,
        clock: () => now,
      );
      final pending = await repoA.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList(utf8('alpha')),
      );
      now = now.add(const Duration(minutes: 1));
      final stranded = await repoA.enqueue(
        operationType: SyncOperationType.update,
        payload: Uint8List.fromList(utf8('beta')),
      );
      now = now.add(const Duration(minutes: 1));
      final failed = await repoA.enqueue(
        operationType: SyncOperationType.delete,
        payload: Uint8List.fromList(utf8('gamma')),
      );
      // Crash mid-push: one item stranded in_progress, one pushed-and-failed
      // (realistic path: in_progress → failed stamps lastAttemptAt for the
      // backoff gate), one never attempted.
      await repoA.markInProgress(stranded.id);
      await repoA.markInProgress(failed.id);
      await repoA.markFailed(failed.id);

      // --- process 1 dies; the DB file holds exactly the row-codec rows ----
      final rows = (await storeA.getAll())
          .map(syncQueueItemToRow)
          .toList(growable: false);

      // --- process 2: cold start reads the rows back ------------------------
      final storeB = queueStore();
      for (final row in rows) {
        await storeB.insert(syncQueueItemFromRow(row));
      }
      final repoB = LocalSyncQueueRepository(
        store: storeB,
        cipher: cipher,
        clock: () => now,
      );

      // Every state survived the restart.
      final afterRestart = await repoB.getAll();
      expect(afterRestart.map((i) => i.id).toSet(),
          {pending.id, stranded.id, failed.id});
      expect((await repoB.getById(stranded.id))!.status,
          SyncQueueStatus.inProgress);
      expect((await repoB.getById(failed.id))!.status, SyncQueueStatus.failed);
      expect(
          (await repoB.getById(pending.id))!.status, SyncQueueStatus.pending);
      // Sealed bytes are byte-identical across the restart — recovery and
      // re-reads never re-encrypt.
      expect((await repoB.getById(stranded.id))!.payload, stranded.payload);
      expect((await repoB.getById(failed.id))!.payload, failed.payload);
      // And they still open to the original plaintexts with the same key.
      expect(await cipher.open((await repoB.getById(pending.id))!.payload),
          equals(utf8('alpha')));
      expect(await cipher.open((await repoB.getById(stranded.id))!.payload),
          equals(utf8('beta')));

      // --- process 2 syncs: recovery + drain ---------------------------------
      final sink = RecordingSyncSink();
      final worker = BackgroundSyncWorker(
        queue: repoB,
        sink: sink,
        clock: () => now,
      );
      final result = await worker.runOnce();

      // The stranded + pending items are delivered; the failed item waits for
      // its backoff window (never re-pushed by this run).
      expect(result.pushed, 2);
      expect(result.failed, 0);
      expect(sink.pushed.map((i) => i.id).toSet(),
          containsAll([pending.id, stranded.id]));
      // Oldest-first ordering survives the restart: pending (t0) before the
      // recovered stranded item (t1).
      expect(sink.pushed.first.id, pending.id);
      // Every delivered payload still opens to its original plaintext.
      final opened = sink.pushed.map((i) => cipher.open(i.payload));
      final texts = await Future.wait(opened);
      expect(texts.map(String.fromCharCodes), containsAll(['alpha', 'beta']));
    });

    test('queue ordering survives restart (getPending stays oldest-first)',
        () async {
      final seed = [
        SyncQueueItem(
          id: 'q-oldest',
          operationType: SyncOperationType.create,
          payload: Uint8List.fromList([1]),
          createdAt: DateTime(2026, 8, 1),
        ),
        SyncQueueItem(
          id: 'q-mid',
          operationType: SyncOperationType.create,
          payload: Uint8List.fromList([2]),
          createdAt: DateTime(2026, 8, 2),
        ),
        SyncQueueItem(
          id: 'q-newest',
          operationType: SyncOperationType.create,
          payload: Uint8List.fromList([3]),
          createdAt: DateTime(2026, 8, 3),
        ),
      ];

      // Restart through the row boundary.
      final storeB = queueStore();
      for (final item in seed) {
        await storeB.insert(syncQueueItemFromRow(syncQueueItemToRow(item)));
      }
      final repoB =
          LocalSyncQueueRepository(store: storeB, cipher: testCipher());

      final pending = await repoB.getPending();

      expect(pending.map((i) => i.id), ['q-oldest', 'q-mid', 'q-newest']);
    });

    test('recoverInterrupted after a restart never corrupts payloads',
        () async {
      final cipher = testCipher();
      final store = queueStore();
      final repoA = LocalSyncQueueRepository(store: store, cipher: cipher);
      final raw = Uint8List.fromList(utf8('stranded-plaintext'));
      final item = await repoA.enqueue(
        operationType: SyncOperationType.create,
        payload: raw,
      );
      await repoA.markInProgress(item.id);

      // Restart.
      final storeB = queueStore();
      await storeB.insert(syncQueueItemFromRow(
          syncQueueItemToRow((await repoA.getById(item.id))!)));
      final repoB = LocalSyncQueueRepository(store: storeB, cipher: cipher);

      await repoB.recoverInterrupted();

      final recovered = await repoB.getById(item.id);
      expect(recovered!.status, SyncQueueStatus.pending);
      // Sealed bytes untouched by recovery; still openable.
      expect(recovered.payload, item.payload);
      expect(await cipher.open(recovered.payload), equals(raw));
    });
  });
}
