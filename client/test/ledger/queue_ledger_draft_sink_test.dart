import 'dart:typed_data';

import 'package:civic_commons/ledger/data/queue_ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_draft_record.dart';
import 'package:civic_commons/ledger/domain/ledger_draft_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_post_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  late InMemoryEntityStore<LedgerDraftRecord> draftStore;
  late InMemoryEntityStore<SyncQueueItem> queueStore;
  late LocalSyncQueueRepository syncQueue;
  late QueueLedgerDraftSink sink;

  setUp(() {
    draftStore = InMemoryEntityStore<LedgerDraftRecord>((r) => r.id);
    queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
    syncQueue =
        LocalSyncQueueRepository(store: queueStore, cipher: testCipher());
    sink = QueueLedgerDraftSink(
      draftStore: draftStore,
      syncQueue: syncQueue,
    );
  });

  const draft = LedgerDraft(
    category: LedgerCategory.civicInfrastructure,
    pinCode: '800001',
    headline: 'Boring Road drainage',
    body: 'Third week stopped.',
  );

  group('QueueLedgerDraftSink (Task 7.4)', () {
    test('save persists the draft locally FIRST (offline-first)', () async {
      final id = await sink.save(draft);

      final stored = await draftStore.getById(id);
      expect(stored, isNotNull);
      expect(stored!.category, LedgerCategory.civicInfrastructure);
      expect(stored.pinCode, '800001');
      expect(stored.headline, 'Boring Road drainage');
      expect(stored.body, 'Third week stopped.');
      expect(stored.createdAt, isNotNull);
    });

    test('save enqueues ONE sealed mutation for sync', () async {
      final id = await sink.save(draft);

      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.create);
      expect(queued.first.status, SyncQueueStatus.pending);
      expect(queued.first.id, isNot(id),
          reason: 'queue item id and local draft id are independent');
    });

    test('the queued payload is SEALED — never the plaintext frame', () async {
      await sink.save(draft);

      final queued = (await syncQueue.getAll()).single;
      final plaintext = encodeLedgerPostFrame(const LedgerPostWireFrame(
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'Boring Road drainage',
        body: 'Third week stopped.',
      ));

      // Byte-level proof: the stored payload differs from the raw frame…
      expect(_bytesEqual(queued.payload, plaintext), isFalse,
          reason: 'queue must never persist plaintext draft bytes');
      // …and opens back to the original via the queue cipher.
      final opened = await testCipher().open(queued.payload);
      final frame = decodeLedgerPostFrame(opened);
      expect(frame.category, LedgerCategory.civicInfrastructure);
      expect(frame.pinCode, '800001');
      expect(frame.headline, 'Boring Road drainage');
      expect(frame.body, 'Third week stopped.');
    });

    test('queue item id is a UUID v4 idempotency key (Task 5.2)', () async {
      final keyRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      await sink.save(draft);

      final queued = (await syncQueue.getAll()).single;
      expect(queued.id, matches(keyRegex));
    });

    test('localDrafts returns the persisted snapshot', () async {
      final id = await sink.save(draft);

      final local = await sink.localDrafts();
      expect(local, hasLength(1));
      expect(local.first.id, id);
      expect(local.first.headline, 'Boring Road drainage');
    });

    test('draft record row codec round-trips every field (Task 5.6 bounds)',
        () async {
      final t = DateTime.fromMicrosecondsSinceEpoch(1785999000123456);
      final record = LedgerDraftRecord(
        id: 'd1',
        category: LedgerCategory.breakingLocal,
        pinCode: '110001',
        headline: 'H',
        body: 'B',
        createdAt: t,
      );

      final restored = ledgerDraftRecordFromRow(ledgerDraftRecordToRow(record));

      expect(restored.id, 'd1');
      expect(restored.category, LedgerCategory.breakingLocal);
      expect(restored.pinCode, '110001');
      expect(restored.headline, 'H');
      expect(restored.body, 'B');
      expect(restored.createdAt, t); // microsecond-exact
    });

    test('unknown category wire name in a draft row throws (strict bounds)',
        () {
      final row = ledgerDraftRecordToRow(LedgerDraftRecord(
        id: 'd1',
        category: LedgerCategory.consumerWatch,
        pinCode: '800001',
        headline: 'H',
        body: 'B',
        createdAt: DateTime(2026, 8, 1),
      ));
      expect(
        () => ledgerDraftRecordFromRow({...row, 'category': 'bogus'}),
        throwsArgumentError,
      );
    });

    test('a failing local persist propagates (no silent partial enqueue)',
        () async {
      final throwing = _ThrowingDraftStore();
      final localSink = QueueLedgerDraftSink(
        draftStore: throwing,
        syncQueue: syncQueue,
      );

      await expectLater(localSink.save(draft), throwsA(isA<StateError>()));
      // Nothing was queued — local-first means the queue is never written
      // when the durable local write failed.
      expect(await syncQueue.getAll(), isEmpty);
    });

    test('multiple saves order drafts by insertion (FIFO local snapshot)',
        () async {
      final t0 = DateTime(2026, 8, 1, 10);
      final t1 = DateTime(2026, 8, 1, 11);
      var now = t0;
      final clocked = QueueLedgerDraftSink(
        draftStore: draftStore,
        syncQueue: syncQueue,
        clock: () => now,
      );

      await clocked.save(draft);
      now = t1;
      await clocked.save(const LedgerDraft(
        category: LedgerCategory.studentRights,
        pinCode: '800001',
        headline: 'Exam leak',
        body: '',
      ));

      final local = await clocked.localDrafts();
      expect(local, hasLength(2));
      expect(local[0].createdAt, t0);
      expect(local[1].createdAt, t1);
    });
  });
}

bool _bytesEqual(Uint8List a, Uint8List b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

class _ThrowingDraftStore implements EntityStore<LedgerDraftRecord> {
  @override
  Future<List<LedgerDraftRecord>> getAll() async => const [];

  @override
  Future<LedgerDraftRecord?> getById(String id) async => null;

  @override
  Future<void> insert(LedgerDraftRecord entity) async {
    throw StateError('disk full');
  }

  @override
  Future<void> update(LedgerDraftRecord entity) async {}

  @override
  Future<void> delete(String id) async {}
}
