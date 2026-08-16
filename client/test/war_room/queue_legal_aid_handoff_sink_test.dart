import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/war_room/data/queue_legal_aid_handoff_sink.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  group('QueueLegalAidHandoffSink (Task 8.6)', () {
    late InMemoryEntityStore<LegalAidHandoff> handoffStore;
    late InMemoryEntityStore<SyncQueueItem> queueStore;
    late LocalSyncQueueRepository syncQueue;
    late QueueLegalAidHandoffSink sink;

    setUp(() {
      handoffStore = InMemoryEntityStore<LegalAidHandoff>((h) => h.id);
      queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: testCipher());
      sink = QueueLegalAidHandoffSink(
        handoffStore: handoffStore,
        syncQueue: syncQueue,
      );
    });

    LegalAidHandoff handoff({String id = ''}) => LegalAidHandoff(
          id: id,
          caseNumber: 'CC-0047',
          reportSignature: 'abcDEF123_signature',
          analystId: 'AN-0003',
          queuedAt: DateTime.utc(2026, 8, 10, 12, 30),
        );

    test('queue persists locally AND enqueues a sealed handoff item', () async {
      final id = await sink.queue(handoff());

      // 1. Local-first — the handoff is in the encrypted store immediately.
      expect(handoffStore.length, 1);
      final local = await handoffStore.getById(id);
      expect(local!.caseNumber, 'CC-0047');
      expect(local.reportSignature, 'abcDEF123_signature');
      expect(local.analystId, 'AN-0003');

      // 2. A sealed queue item exists with the handoff id as its id
      //    (the idempotency key).
      final pending = await syncQueue.getPending();
      expect(pending, hasLength(1));
      final item = pending.single;
      expect(item.operationType, SyncOperationType.create);
      expect(item.id, id);

      // 3. Opening the sealed payload recovers the strict handoff frame.
      final opened = await testCipher().open(item.payload);
      final envelope =
          LegalAidHandoffEnvelope.decode(String.fromCharCodes(opened));
      expect(envelope.caseNumber, 'CC-0047');
      expect(envelope.reportSignature, 'abcDEF123_signature');
      expect(envelope.analystId, 'AN-0003');
    });

    test('mints a UUID v4 id when the caller passes a draft (empty id)',
        () async {
      final id = await sink.queue(handoff());
      expect(
          id,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
          reason: 'the minted id must be a UUID v4');
    });

    test(
        'BYTE-LEVEL PROOF: the raw queue payload contains zero plaintext '
        'frame fields', () async {
      await sink.queue(handoff());
      final raw = (await queueStore.getAll()).single.payload;
      final rawString = String.fromCharCodes(raw);
      expect(rawString.contains('CC-0047'), isFalse,
          reason: 'the case stamp must never survive in plaintext');
      expect(rawString.contains('AN-0003'), isFalse,
          reason: 'the blinded analyst handle must never survive');
      expect(rawString.contains('report_signature'), isFalse,
          reason: 'the frame field names must not survive unsealed');
    });

    test('localHandoffs returns the persisted snapshot (cold-start recovery)',
        () async {
      await sink.queue(handoff());
      final snapshot = await sink.localHandoffs();
      expect(snapshot, hasLength(1));
      expect(snapshot.single.caseNumber, 'CC-0047');
    });

    test('respects a caller-supplied id (idempotent replay preserves it)',
        () async {
      final id = await sink.queue(handoff(id: 'fixed-id-1234'));
      expect(id, 'fixed-id-1234');
      expect((await handoffStore.getAll()).single.id, 'fixed-id-1234');
    });
  });
}
