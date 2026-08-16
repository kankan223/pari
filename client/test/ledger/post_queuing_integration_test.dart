import 'package:civic_commons/ledger/data/queue_ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_draft_record.dart';
import 'package:civic_commons/ledger/domain/ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_post_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_ledger_compose_bloc.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// VERIFY (Task 7.4): integration — a composed Ledger post is persisted
/// locally FIRST (offline-first), queued as a SEALED envelope, and the sync
/// worker drains it back to the exact civic frame bytes with no plaintext
/// ever touching the queue store.
///
/// Per repo convention the restart boundary is exercised at the exact row
/// codec: the draft row written by process 1 is round-tripped through
/// [ledgerDraftRecordToRow]/[ledgerDraftRecordFromRow] and the sealed queue
/// row through [syncQueueItemToRow]/[syncQueueItemFromRow].
void main() {
  group('Task 7.4 - post creation & queuing end-to-end', () {
    test('compose -> local persist -> sealed queue -> drained intact',
        () async {
      final cipher = testCipher();
      final draftStore = InMemoryEntityStore<LedgerDraftRecord>((r) => r.id);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: cipher);
      final sink = QueueLedgerDraftSink(
        draftStore: draftStore,
        syncQueue: syncQueue,
      );
      final bloc = LocalLedgerComposeBloc(drafts: sink);

      // The user composes and submits while OFFLINE.
      await bloc.start();
      await bloc.setCategory(LedgerCategory.civicInfrastructure);
      await bloc.setPinCode('800001');
      await bloc.setHeadline('Boring Road drainage');
      await bloc.setBody('Third week stopped.');
      await bloc.submit();
      expect(bloc.current.isSubmitted, isTrue);

      // --- local-first: the draft row exists immediately --------------------
      final drafts = await sink.localDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.first.headline, 'Boring Road drainage');
      expect(drafts.first.category, LedgerCategory.civicInfrastructure);

      // --- the queue holds exactly ONE sealed envelope -----------------------
      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.create);
      final storedPayload = queued.first.payload;

      // --- cold restart: rows round-trip through the exact codecs ------------
      final draftRow =
          ledgerDraftRecordToRow((await draftStore.getAll()).single);
      final draftStoreB = InMemoryEntityStore<LedgerDraftRecord>((r) => r.id);
      await draftStoreB.insert(ledgerDraftRecordFromRow(draftRow));
      final queueStoreB = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      await queueStoreB
          .insert(syncQueueItemFromRow(syncQueueItemToRow(queued.single)));

      // Restarted app recovers the local draft immediately.
      final restartedSink = QueueLedgerDraftSink(
        draftStore: draftStoreB,
        syncQueue: LocalSyncQueueRepository(store: queueStoreB, cipher: cipher),
      );
      final recovered = await restartedSink.localDrafts();
      expect(recovered.single.headline, 'Boring Road drainage');

      // --- sync drains the sealed envelope; bytes never changed --------------
      final sinkB =
          LocalSyncQueueRepository(store: queueStoreB, cipher: cipher);
      final recording = RecordingSyncSink();
      final worker = BackgroundSyncWorker(queue: sinkB, sink: recording);
      final result = await worker.runOnce();
      expect(result.pushed, 1);

      // The pushed payload is byte-identical to the stored sealed bytes and
      // opens to the EXACT civic frame — no drift across the restart.
      expect(recording.pushed.single.payload, storedPayload);
      final frame = decodeLedgerPostFrame(
          await cipher.open(recording.pushed.single.payload));
      expect(frame.category, LedgerCategory.civicInfrastructure);
      expect(frame.pinCode, '800001');
      expect(frame.headline, 'Boring Road drainage');
      expect(frame.body, 'Third week stopped.');
    });

    test('multiple offline posts queue in order and drain oldest-first',
        () async {
      final cipher = testCipher();
      final draftStore = InMemoryEntityStore<LedgerDraftRecord>((r) => r.id);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      var now = DateTime(2026, 8, 1, 9);
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore,
        cipher: cipher,
        clock: () => now,
      );
      final sink = QueueLedgerDraftSink(
        draftStore: draftStore,
        syncQueue: syncQueue,
        clock: () => now,
      );

      await sink.save(const LedgerDraft(
        category: LedgerCategory.breakingLocal,
        pinCode: '800001',
        headline: 'First',
        body: '',
      ));
      now = now.add(const Duration(minutes: 5));
      await sink.save(const LedgerDraft(
        category: LedgerCategory.consumerWatch,
        pinCode: '560001',
        headline: 'Second',
        body: '',
      ));

      final recording = RecordingSyncSink();
      final worker = BackgroundSyncWorker(
          queue: syncQueue, sink: recording, clock: () => now);
      final result = await worker.runOnce();

      expect(result.pushed, 2);
      expect(recording.pushed.first.id, isNot(recording.pushed.last.id));
      final opened = await Future.wait(
          recording.pushed.map((i) => cipher.open(i.payload)));
      final frames = opened.map(decodeLedgerPostFrame).toList();
      expect(frames.map((f) => f.headline), ['First', 'Second']);
      expect(frames.map((f) => f.pinCode), ['800001', '560001']);
    });

    test('sealed payloads never contain plaintext draft bytes', () async {
      final cipher = testCipher();
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final sink = QueueLedgerDraftSink(
        draftStore: InMemoryEntityStore<LedgerDraftRecord>((r) => r.id),
        syncQueue: LocalSyncQueueRepository(store: queueStore, cipher: cipher),
      );

      await sink.save(const LedgerDraft(
        category: LedgerCategory.satireAndCulture,
        pinCode: '800001',
        headline: 'Plaintext headline must never persist',
        body: 'Plaintext body must never persist',
      ));

      final stored = (await queueStore.getAll()).single;
      final storedText = String.fromCharCodes(stored.payload);
      expect(storedText.contains('Plaintext headline'), isFalse);
      expect(storedText.contains('Plaintext body'), isFalse);
      expect(storedText.contains('800001'), isFalse);
    });
  });
}
