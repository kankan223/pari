import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_conversation_repository.dart';
import 'package:civic_commons/repository/data/local_message_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/conflict_resolution.dart';
import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/repository/domain/sync_conflict_resolver.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';

import 'fakes.dart';

LocalSyncQueueRepository testQueue() => LocalSyncQueueRepository(
      store: queueStore(),
      cipher: testCipher(),
    );

/// VERIFY (Task 3.2): the repository returns cached local data immediately,
/// before any sync attempt — and NEVER touches the network during local reads.
void main() {
  group('LocalFirstRepository - cached data before sync', () {
    test('fetchLocal returns the locally cached snapshot with zero network I/O',
        () async {
      final store = InMemoryEntityStore<Message>((m) => m.id);
      final repo = LocalMessageRepository(
        store: store,
        syncQueue: testQueue(),
        // If fetchLocal ever calls the sink, this throws and fails the test.
        sink: ExplodingSyncSink(),
      );
      // Seed the local store (as if previously synced / cached).
      await store.insert(Message(
        id: 'm1',
        conversationId: 'conv1',
        ciphertext: Uint8List.fromList([1, 2, 3]),
        delivered: true,
      ));

      final cached = await repo.fetchLocal();

      expect(cached.map((m) => m.id), ['m1']);
    });

    test('fetchLocal succeeds even when the remote is entirely unavailable',
        () async {
      final store = InMemoryEntityStore<Conversation>((c) => c.id);
      final repo = LocalConversationRepository(
        store: store,
        syncQueue: testQueue(),
        sink: ExplodingSyncSink(),
      );
      await store.insert(Conversation(
        id: 'c1',
        participantHash: 'blindhash-1',
        encryptedSessionState: Uint8List.fromList([9, 8, 7]),
      ));

      final cached = await repo.fetchLocal();

      expect(cached, hasLength(1));
      expect(cached.first.participantHash, 'blindhash-1');
    });

    test('reads do not drain the queue nor send anything to the sink',
        () async {
      final queue = testQueue();
      final sink = RecordingSyncSink();
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: queue,
        sink: sink,
      );
      // A pending item exists, but a pure read must NOT trigger sync.
      await queue.create(pendingItem('q1'));

      final all = await repo.getAll();
      await repo.getByConversation('conv1');
      await repo.getUndelivered();

      expect(all, isEmpty);
      expect(sink.pushed, isEmpty);
    });

    test('sync pushes only pending items and marks them success', () async {
      final rawQueueStore = queueStore();
      final queue = LocalSyncQueueRepository(
        store: rawQueueStore,
        cipher: testCipher(),
      );
      final sink = RecordingSyncSink();
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: queue,
        sink: sink,
      );
      await queue.create(pendingItem('q1'));
      await queue.create(pendingItem('q2'));
      // Already-succeeded items must not be re-pushed. Seed directly into
      // the store, bypassing create() (which forces every item to pending).
      await rawQueueStore.insert(
        pendingItem('q3').copyWith(status: SyncQueueStatus.success),
      );

      final result = await repo.sync();

      expect(result.pushed, 2);
      expect(result.failed, 0);
      expect(result.allSucceeded, isTrue);
      expect(sink.pushed.map((i) => i.id), containsAll(['q1', 'q2']));
      expect(sink.pushed.map((i) => i.id), isNot(contains('q3')));
      // Items are now marked success and dropped from the pending drain.
      expect((await queue.getPending()), isEmpty);
    });

    test('sync records failures and keeps them for retry', () async {
      final queue = testQueue();
      final sink = RecordingSyncSink()..acknowledge = false;
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: queue,
        sink: sink,
      );
      await queue.create(pendingItem('q1'));
      await queue.create(pendingItem('q2'));

      final result = await repo.sync();

      expect(result.pushed, 0);
      expect(result.failed, 2);
      expect(result.allSucceeded, isFalse);
      // Failed items remain retrievable with an incremented retry counter.
      final pending = await queue.getPending();
      expect(pending, isEmpty);
      expect((await queue.getById('q1'))!.retryCount, 1);
      expect((await queue.getById('q1'))!.status, SyncQueueStatus.failed);
    });

    test('sync with an empty queue is a no-op', () async {
      final sink = RecordingSyncSink();
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: testQueue(),
        sink: sink,
      );

      final result = await repo.sync();

      expect(result.pushed, 0);
      expect(result.failed, 0);
      expect(sink.pushed, isEmpty);
    });

    test('sync drops a 409-conflicted item (remote wins) and counts it',
        () async {
      final queue = testQueue();
      final item = await queue.create(pendingItem('q1'));
      final sink = RecordingSyncSink()
        ..scriptConflict = MutationVersion(
          entityId: 'q1',
          timestamp: DateTime(2026, 8, 4, 13),
          serverAcknowledged: true,
          authorHash: 'hash-remote',
        );
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: queue,
        sink: sink,
      );

      final result = await repo.sync();

      expect(result.pushed, 0);
      expect(result.failed, 0);
      expect(result.conflicts, 1);
      expect(result.allSucceeded, isFalse);
      // The superseded local mutation is dropped, not retried.
      expect(await queue.getById(item.id), isNull);
    });

    test('sync counts a local-wins conflict as a retry, not a loss', () async {
      final queue = testQueue();
      final item = await queue.create(pendingItem('q1'));
      final sink = RecordingSyncSink()
        ..scriptConflict = MutationVersion(
          entityId: 'q1',
          timestamp: DateTime(2026, 8, 1, 10), // older than the local edit
          serverAcknowledged: true,
          authorHash: 'hash-remote',
        );
      final repo = LocalMessageRepository(
        store: InMemoryEntityStore<Message>((m) => m.id),
        syncQueue: queue,
        sink: sink,
        conflictResolver: const SyncConflictResolver(
          policy: _TimestampFirstPolicy(),
        ),
      );

      final result = await repo.sync();

      expect(result.pushed, 0);
      expect(result.failed, 1);
      expect(result.conflicts, 0);
      final after = await queue.getById(item.id);
      expect(after!.status, SyncQueueStatus.failed);
    });
  });
}

/// Deterministic newer-timestamp-wins policy for local-wins conflict tests.
class _TimestampFirstPolicy implements ConflictResolutionPolicy {
  const _TimestampFirstPolicy();

  @override
  ConflictResolution resolve({
    required MutationVersion local,
    required MutationVersion remote,
  }) {
    final winner = local.timestamp.isAfter(remote.timestamp) ? local : remote;
    return ConflictResolution(
      winner == local
          ? ConflictDecision.applyLocal
          : ConflictDecision.applyRemote,
      winner,
    );
  }
}
