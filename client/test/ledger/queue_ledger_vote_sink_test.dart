import 'dart:typed_data';

import 'package:civic_commons/ledger/data/queue_ledger_vote_sink.dart';
import 'package:civic_commons/ledger/domain/ledger_vote.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_record.dart';
import 'package:civic_commons/ledger/domain/ledger_vote_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  late InMemoryEntityStore<LedgerVoteRecord> voteStore;
  late InMemoryEntityStore<SyncQueueItem> queueStore;
  late LocalSyncQueueRepository syncQueue;
  late QueueLedgerVoteSink sink;

  setUp(() {
    voteStore = InMemoryEntityStore<LedgerVoteRecord>((r) => r.postId);
    queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
    syncQueue =
        LocalSyncQueueRepository(store: queueStore, cipher: testCipher());
    sink = QueueLedgerVoteSink(
      voteStore: voteStore,
      syncQueue: syncQueue,
    );
  });

  const upvote = LedgerVote(
    postId: 'post_abc123',
    direction: LedgerVoteDirection.up,
  );

  group('QueueLedgerVoteSink (Task 7.5)', () {
    test('save persists the vote record locally FIRST (offline-first)',
        () async {
      await sink.save(upvote);

      final stored = await voteStore.getById('post_abc123');
      expect(stored, isNotNull);
      expect(stored!.direction, LedgerVoteDirection.up);
      expect(stored.updatedAt, isNotNull);
    });

    test('save enqueues ONE sealed update mutation for sync', () async {
      await sink.save(upvote);

      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.update);
      expect(queued.first.status, SyncQueueStatus.pending);
    });

    test('the queued payload is SEALED — never the plaintext frame', () async {
      await sink.save(upvote);

      final queued = (await syncQueue.getAll()).single;
      final plaintext = encodeLedgerVoteFrame(
        const LedgerVoteWireFrame(
          postId: 'post_abc123',
          direction: LedgerVoteDirection.up,
        ),
      );

      expect(_bytesEqual(queued.payload, plaintext), isFalse,
          reason: 'queue must never persist plaintext vote bytes');
      final opened = await testCipher().open(queued.payload);
      final frame = decodeLedgerVoteFrame(opened);
      expect(frame.postId, 'post_abc123');
      expect(frame.direction, LedgerVoteDirection.up);
    });

    test('queue item id is a UUID v4 idempotency key (Task 5.2)', () async {
      final keyRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      await sink.save(upvote);
      expect((await syncQueue.getAll()).single.id, matches(keyRegex));
    });

    test('re-voting the same post overwrites the record and queues again',
        () async {
      await sink.save(upvote);
      await sink.save(const LedgerVote(
        postId: 'post_abc123',
        direction: LedgerVoteDirection.down,
      ));

      final stored = await voteStore.getById('post_abc123');
      expect(stored!.direction, LedgerVoteDirection.down);
      // Two mutations queued (toggle up -> down), both sealed.
      expect(await syncQueue.getAll(), hasLength(2));
    });

    test('localVotes returns the recovery snapshot', () async {
      await sink.save(upvote);
      await sink.save(const LedgerVote(
        postId: 'post_xyz',
        direction: LedgerVoteDirection.down,
      ));

      final local = await sink.localVotes();
      expect(local, hasLength(2));
      expect(
          local.map((r) => r.postId), containsAll(['post_abc123', 'post_xyz']));
    });

    test('vote record row codec round-trips exactly', () async {
      final t = DateTime.fromMicrosecondsSinceEpoch(1785999000123456);
      final record = LedgerVoteRecord(
        postId: 'p1',
        direction: LedgerVoteDirection.down,
        updatedAt: t,
      );

      final restored = ledgerVoteRecordFromRow(ledgerVoteRecordToRow(record));

      expect(restored.postId, 'p1');
      expect(restored.direction, LedgerVoteDirection.down);
      expect(restored.updatedAt, t); // microsecond-exact
    });

    test('unknown direction in a vote row throws (strict bounds)', () {
      final row = ledgerVoteRecordToRow(LedgerVoteRecord(
        postId: 'p1',
        direction: LedgerVoteDirection.up,
        updatedAt: DateTime(2026, 8, 1),
      ));
      expect(
        () => ledgerVoteRecordFromRow({...row, 'direction': 'bogus'}),
        throwsArgumentError,
      );
    });

    test('a failing local persist propagates — no silent partial enqueue',
        () async {
      final throwing = _ThrowingVoteStore();
      final localSink = QueueLedgerVoteSink(
        voteStore: throwing,
        syncQueue: syncQueue,
      );

      await expectLater(localSink.save(upvote), throwsA(isA<StateError>()));
      expect(await syncQueue.getAll(), isEmpty);
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

class _ThrowingVoteStore implements EntityStore<LedgerVoteRecord> {
  @override
  Future<List<LedgerVoteRecord>> getAll() async => const [];

  @override
  Future<LedgerVoteRecord?> getById(String id) async => null;

  @override
  Future<void> insert(LedgerVoteRecord entity) async {
    throw StateError('disk full');
  }

  @override
  Future<void> update(LedgerVoteRecord entity) async {}

  @override
  Future<void> delete(String id) async {}
}
