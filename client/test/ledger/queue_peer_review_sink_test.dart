import 'dart:typed_data';

import 'package:civic_commons/ledger/data/queue_peer_review_sink.dart';
import 'package:civic_commons/ledger/domain/peer_review.dart';
import 'package:civic_commons/ledger/domain/peer_review_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  late InMemoryEntityStore<PeerReviewRecord> reviewStore;
  late InMemoryEntityStore<SyncQueueItem> queueStore;
  late LocalSyncQueueRepository syncQueue;
  late QueuePeerReviewSink sink;

  setUp(() {
    reviewStore = InMemoryEntityStore<PeerReviewRecord>((r) => r.postId);
    queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
    syncQueue =
        LocalSyncQueueRepository(store: queueStore, cipher: testCipher());
    sink = QueuePeerReviewSink(
      reviewStore: reviewStore,
      syncQueue: syncQueue,
    );
  });

  const approve = PeerReviewSubmission(
    postId: 'post_abc123',
    decision: PeerReviewDecision.approved,
  );

  group('QueuePeerReviewSink (Task 7.6)', () {
    test('save persists the decision record locally FIRST (offline-first)',
        () async {
      await sink.save(approve);

      final stored = await reviewStore.getById('post_abc123');
      expect(stored, isNotNull);
      expect(stored!.decision, PeerReviewDecision.approved);
      expect(stored.reviewedAt, isNotNull);
    });

    test('save enqueues ONE sealed update mutation for sync', () async {
      await sink.save(approve);

      final queued = await syncQueue.getAll();
      expect(queued, hasLength(1));
      expect(queued.first.operationType, SyncOperationType.update);
      expect(queued.first.status, SyncQueueStatus.pending);
    });

    test('the queued payload is SEALED — never the plaintext frame', () async {
      await sink.save(approve);

      final queued = (await syncQueue.getAll()).single;
      final plaintext = encodePeerReviewFrame(
        const PeerReviewWireFrame(
          postId: 'post_abc123',
          decision: PeerReviewDecision.approved,
        ),
      );

      expect(_bytesEqual(queued.payload, plaintext), isFalse,
          reason: 'queue must never persist plaintext review bytes');
      final opened = await testCipher().open(queued.payload);
      final frame = decodePeerReviewFrame(opened);
      expect(frame.postId, 'post_abc123');
      expect(frame.decision, PeerReviewDecision.approved);
    });

    test('queue item id is a UUID v4 idempotency key (Task 5.2)', () async {
      final keyRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      await sink.save(approve);
      expect((await syncQueue.getAll()).single.id, matches(keyRegex));
    });

    test('re-reviewing the same post overwrites the record and queues again',
        () async {
      await sink.save(approve);
      await sink.save(const PeerReviewSubmission(
        postId: 'post_abc123',
        decision: PeerReviewDecision.flagged,
      ));

      final stored = await reviewStore.getById('post_abc123');
      expect(stored!.decision, PeerReviewDecision.flagged);
      // Two decisions queued (approve -> flag), both sealed.
      expect(await syncQueue.getAll(), hasLength(2));
    });

    test('localDecisions returns the recovery snapshot', () async {
      await sink.save(approve);
      await sink.save(const PeerReviewSubmission(
        postId: 'post_xyz',
        decision: PeerReviewDecision.rejected,
      ));

      final local = await sink.localDecisions();
      expect(local, hasLength(2));
      expect(
          local.map((r) => r.postId), containsAll(['post_abc123', 'post_xyz']));
    });

    test('review record row codec round-trips exactly', () async {
      final t = DateTime.fromMicrosecondsSinceEpoch(1785999000123456);
      final record = PeerReviewRecord(
        postId: 'p1',
        decision: PeerReviewDecision.flagged,
        reviewedAt: t,
      );

      final restored = peerReviewRecordFromRow(peerReviewRecordToRow(record));

      expect(restored.postId, 'p1');
      expect(restored.decision, PeerReviewDecision.flagged);
      expect(restored.reviewedAt, t); // microsecond-exact
    });

    test('unknown decision in a review row throws (strict bounds)', () {
      final row = peerReviewRecordToRow(PeerReviewRecord(
        postId: 'p1',
        decision: PeerReviewDecision.approved,
        reviewedAt: DateTime(2026, 8, 1),
      ));
      expect(
        () => peerReviewRecordFromRow({...row, 'decision': 'bogus'}),
        throwsArgumentError,
      );
    });

    test('a failing local persist propagates — no silent partial enqueue',
        () async {
      final throwing = _ThrowingReviewStore();
      final localSink = QueuePeerReviewSink(
        reviewStore: throwing,
        syncQueue: syncQueue,
      );

      await expectLater(localSink.save(approve), throwsA(isA<StateError>()));
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

class _ThrowingReviewStore implements EntityStore<PeerReviewRecord> {
  @override
  Future<List<PeerReviewRecord>> getAll() async => const [];

  @override
  Future<PeerReviewRecord?> getById(String id) async => null;

  @override
  Future<void> insert(PeerReviewRecord entity) async {
    throw StateError('disk full');
  }

  @override
  Future<void> update(PeerReviewRecord entity) async {}

  @override
  Future<void> delete(String id) async {}
}
