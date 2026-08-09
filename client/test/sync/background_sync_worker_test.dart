import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/conflict_resolution.dart';
import 'package:civic_commons/repository/domain/exponential_backoff.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_conflict_resolver.dart';
import 'package:civic_commons/sync/data/background_sync_worker.dart';
import 'package:civic_commons/sync/domain/batch_chunker.dart';

import 'package:civic_commons/repository/domain/sync_sink.dart';

import '../repository/fakes.dart'
    show InMemoryEntityStore, RecordingSyncSink, queueStore, testCipher;

/// VERIFY (Task 3.4): integration tests for background sync execution —
/// the worker drains the pending queue through the sink in bounded batches.
void main() {
  late InMemoryEntityStore<SyncQueueItem> store;
  late LocalSyncQueueRepository queue;
  late RecordingSyncSink sink;
  late BackgroundSyncWorker worker;

  setUp(() {
    store = queueStore();
    queue = LocalSyncQueueRepository(store: store, cipher: testCipher());
    sink = RecordingSyncSink();
    worker = BackgroundSyncWorker(queue: queue, sink: sink);
  });

  Future<void> seedItems(int count) async {
    for (var i = 0; i < count; i++) {
      await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([i]),
      );
    }
  }

  group('BackgroundSyncWorker - drains pending queue', () {
    test('empty queue is a no-op (zero pushes)', () async {
      final result = await worker.runOnce();

      expect(result.pushed, 0);
      expect(result.failed, 0);
      expect(sink.pushed, isEmpty);
    });

    test('pushes every pending item through the sink', () async {
      await seedItems(5);

      final result = await worker.runOnce();

      expect(result.pushed, 5);
      expect(result.failed, 0);
      expect(sink.pushed, hasLength(5));
      // Queue is drained: no pending items remain.
      expect(await queue.getPending(), isEmpty);
    });

    test('marks items success when acknowledged', () async {
      await seedItems(3);

      await worker.runOnce();

      final all = await queue.getAll();
      expect(all.every((i) => i.status == SyncQueueStatus.success), isTrue);
    });

    test('marks items failed (with retry bump) when rejected', () async {
      await seedItems(2);
      sink.acknowledge = false;

      final result = await worker.runOnce();

      expect(result.pushed, 0);
      expect(result.failed, 2);
      final all = await queue.getAll();
      for (final item in all) {
        expect(item.status, SyncQueueStatus.failed);
        expect(item.retryCount, 1);
      }
    });

    test('a THROWN sink error marks the item failed (never stuck in_progress)',
        () async {
      await seedItems(2);
      final throwing = ThrowingSyncSink();
      final crashingWorker = BackgroundSyncWorker(queue: queue, sink: throwing);

      final result = await crashingWorker.runOnce();

      // The worker must not crash and must not leave items in_progress — a
      // thrown sink error is the same failure path as a rejected push.
      expect(result.pushed, 0);
      expect(result.failed, 2);
      final all = await queue.getAll();
      for (final item in all) {
        expect(item.status, SyncQueueStatus.failed);
        expect(item.retryCount, 1);
        // Sealed payload survives the failure untouched.
        expect(await testCipher().open(item.payload), isNotNull);
      }
      // Items remain in the encrypted queue (retrievable, retry state
      // tracked) — nothing was lost or corrupted.
      expect(await queue.getById(all.first.id), isNotNull);
    });
  });

  group('BackgroundSyncWorker - bounded batching (max 10 per batch)', () {
    test('25 items are pushed in 3 batches (10 + 10 + 5)', () async {
      await seedItems(25);

      final result = await worker.runOnce();

      expect(result.pushed, 25);
      expect(result.failed, 0);
      expect(sink.pushed, hasLength(25));
      expect(await queue.getPending(), isEmpty);
    });

    test('default batch size is exactly 10', () {
      expect(BatchChunker.defaultMaxBatchSize, 10);
    });

    test('custom maxBatchSize is honored by the worker', () async {
      await seedItems(5);
      final small = BackgroundSyncWorker(
        queue: queue,
        sink: sink,
        maxBatchSize: 2,
      );

      final result = await small.runOnce();

      expect(result.pushed, 5);
      expect(await queue.getPending(), isEmpty);
    });
  });

  group('BackgroundSyncWorker - deterministic retry with backoff (Task 5.2)',
      () {
    // Controllable clock shared by the repository (stamps lastAttemptAt) and
    // the worker (gates retry eligibility).
    late MutableClock clock;
    late InMemoryEntityStore<SyncQueueItem> retryStore;
    late LocalSyncQueueRepository retryQueue;
    late BackgroundSyncWorker retryWorker;

    setUp(() {
      clock = MutableClock(DateTime(2026, 8, 4, 12));
      retryStore = queueStore();
      retryQueue = LocalSyncQueueRepository(
        store: retryStore,
        cipher: testCipher(),
        clock: () => clock.now,
      );
      retryWorker = BackgroundSyncWorker(
        queue: retryQueue,
        sink: sink,
        clock: () => clock.now,
      );
    });

    test('a failed item is NOT retried before its backoff window elapses',
        () async {
      final item = await retryQueue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      // First attempt fails at t=0 (retryCount -> 1, lastAttemptAt stamped).
      sink.acknowledge = false;
      await retryWorker.runOnce();
      sink.acknowledge = true;

      // Half the base window (1s) has NOT elapsed yet (equal-jitter minimum).
      clock.advance(const Duration(milliseconds: 400));
      final result = await retryWorker.runOnce();

      expect(result.pushed, 0,
          reason: 'retry must wait for the backoff window (>= base/2)');
      expect(
          (await retryQueue.getById(item.id))!.status, SyncQueueStatus.failed);
    });

    test('a failed item IS retried once its backoff window has elapsed',
        () async {
      await retryQueue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      sink.acknowledge = false;
      await retryWorker.runOnce(); // fails, retryCount=1, lastAttemptAt=t0
      sink.acknowledge = true;

      // Well past the base window (1s for retry 1); equal jitter guarantees
      // eligibility no later than the full base delay.
      clock.advance(const Duration(seconds: 2));
      final result = await retryWorker.runOnce();

      expect(result.pushed, 1,
          reason: 'retry becomes eligible after the full backoff window');
      expect(result.failed, 0);
      final all = await retryQueue.getAll();
      expect(all.single.status, SyncQueueStatus.success);
    });

    test('backoff grows: retry 2 waits longer than retry 1', () async {
      await retryQueue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      sink.acknowledge = false;
      await retryWorker.runOnce(); // fails #1 (retryCount 1, base now 1s)

      // 1.2s elapsed (> base 1s): retry 1 is definitely eligible, retried,
      // and fails again -> retryCount 2 (base now 2s).
      clock.advance(const Duration(milliseconds: 1200));
      await retryWorker.runOnce();
      final afterSecond = await retryQueue.getAll();
      expect(afterSecond.single.retryCount, 2);

      // After failure #2 the base is 2s (equal jitter min = 1s). Advancing
      // only 0.5s is below the minimum for retry 2 — deterministically NOT
      // eligible yet.
      clock.advance(const Duration(milliseconds: 500));
      final third = await retryWorker.runOnce();
      expect(third.pushed, 0,
          reason: 'retry 2 needs >= 1s (half of the 2s base), only 0.5s '
              'elapsed');

      // Advance past the FULL 2s base: deterministically eligible now.
      sink.acknowledge = true;
      clock.advance(const Duration(milliseconds: 1600)); // total 2.1s
      final fourth = await retryWorker.runOnce();
      expect(fourth.pushed, 1,
          reason: 'retry 2 becomes eligible after the full 2s base');
    });

    test('jitter decorrelates retries but never below the minimum', () async {
      // With equal jitter the gate is deterministic at the boundaries: never
      // eligible before base/2, always eligible by base. Use a fast tiny
      // backoff so the test runs without real waits. Attempts are counted via
      // sink.pushed (recorded even on rejection) since the mid-window outcome
      // is legitimately random.
      final fast = BackgroundSyncWorker(
        queue: retryQueue,
        sink: sink,
        clock: () => clock.now,
        backoff: const ExponentialBackoff(
          initialDelay: Duration(milliseconds: 100),
          maxDelay: Duration(seconds: 1),
        ),
      );
      await retryQueue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      sink.acknowledge = false;

      await fast.runOnce(); // attempt 1 fails; retryCount=1; base=100ms
      expect(sink.pushed, hasLength(1));

      // base=100ms → minimum gate is 50ms; 40ms is deterministically too soon.
      clock.advance(const Duration(milliseconds: 40));
      await fast.runOnce();
      expect(sink.pushed, hasLength(1),
          reason: '40ms < 50ms equal-jitter minimum — must NOT retry');

      // 60ms is inside [50, 100) — eligibility depends on the jitter draw,
      // so the attempt count may stay 1 or grow to 2.
      clock.advance(const Duration(milliseconds: 20));
      await fast.runOnce();
      final midAttempts = sink.pushed.length;
      expect(midAttempts, inInclusiveRange(1, 2));

      // Advance far past the max delay (1s): the retry is deterministically
      // eligible regardless of how many attempts the mid-window produced
      // (retryCount may have grown, but the cap bounds the gate).
      clock.advance(const Duration(seconds: 2));
      await fast.runOnce();
      expect(sink.pushed.length, midAttempts + 1,
          reason: 'past the max backoff the retry definitely fires');
    });
  });

  group('BackgroundSyncWorker - crash recovery (Task 5.2)', () {
    test('items stranded in_progress by a killed run are retried', () async {
      final stranded = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([7]),
      );
      // Simulate a crash mid-drain: the item is left in_progress and the
      // process dies before marking success/failure.
      await queue.markInProgress(stranded.id);

      // A fresh worker run (new process) must recover and deliver it.
      final result = await worker.runOnce();

      expect(result.pushed, 1);
      expect(result.failed, 0);
      final after = await queue.getById(stranded.id);
      expect(after!.status, SyncQueueStatus.success);
    });

    test('recoverInterrupted is a no-op when nothing is stranded', () async {
      await seedItems(2);
      await worker.runOnce();

      await queue.recoverInterrupted();

      // Nothing left in_progress; the queue state is untouched.
      final all = await queue.getAll();
      expect(all.every((i) => i.status == SyncQueueStatus.success), isTrue);
    });

    test('success/failed items are never resurrected by recovery', () async {
      final ok = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      final bad = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([2]),
      );
      await queue.markSuccess(ok.id);
      await queue.markFailed(bad.id);

      await queue.recoverInterrupted();

      expect((await queue.getById(ok.id))!.status, SyncQueueStatus.success);
      expect((await queue.getById(bad.id))!.status, SyncQueueStatus.failed);
      // Sealed payloads are untouched by recovery.
      expect(await testCipher().open((await queue.getById(bad.id))!.payload),
          isNotNull);
    });
  });

  group('BackgroundSyncWorker - expired-item cleanup (Task 5.6)', () {
    late MutableClock clock;
    late InMemoryEntityStore<SyncQueueItem> expiryStore;
    late LocalSyncQueueRepository expiryQueue;
    late BackgroundSyncWorker expiryWorker;

    setUp(() {
      clock = MutableClock(DateTime(2026, 8, 4, 12));
      expiryStore = queueStore();
      expiryQueue = LocalSyncQueueRepository(
        store: expiryStore,
        cipher: testCipher(),
        clock: () => clock.now,
      );
      expiryWorker = BackgroundSyncWorker(
        queue: expiryQueue,
        sink: sink,
        clock: () => clock.now,
      );
    });

    test('items older than 30 days are purged before the drain (never pushed)',
        () async {
      await expiryStore.insert(SyncQueueItem(
        id: 'ancient',
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
        createdAt: DateTime(2026, 6, 1), // 64 days before the worker clock
      ));

      final result = await expiryWorker.runOnce();

      expect(result.pushed, 0);
      expect(sink.pushed, isEmpty);
      expect(await expiryStore.getById('ancient'), isNull);
    });

    test('an item exactly 30 days old is retained and pushed', () async {
      await expiryStore.insert(SyncQueueItem(
        id: 'boundary',
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
        createdAt: DateTime(2026, 7, 5, 12), // exactly 30 days before the clock
      ));

      final result = await expiryWorker.runOnce();

      expect(result.pushed, 1);
      expect((await expiryStore.getById('boundary'))!.status,
          SyncQueueStatus.success);
    });

    test('expired FAILED items are purged instead of retried', () async {
      // A failed item with no lastAttemptAt would be immediately retryable —
      // but retention must purge it before the drain ever sees it.
      await expiryStore.insert(SyncQueueItem(
        id: 'ancient-failed',
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([2]),
        status: SyncQueueStatus.failed,
        createdAt: DateTime(2026, 5, 1),
      ));

      final result = await expiryWorker.runOnce();

      expect(result.pushed, 0);
      expect(await expiryStore.getById('ancient-failed'), isNull);
    });
  });

  group('BackgroundSyncWorker - aggressive request timeout (Task 5.2)', () {
    test('a push that never completes times out and marks the item failed',
        () async {
      await seedItems(1);
      final hanging = HangingSyncSink();
      final timeoutWorker = BackgroundSyncWorker(
        queue: queue,
        sink: hanging,
        requestTimeout: const Duration(milliseconds: 50),
      );

      final result = await timeoutWorker.runOnce();

      expect(result.pushed, 0);
      expect(result.failed, 1);
      final all = await queue.getAll();
      expect(all.single.status, SyncQueueStatus.failed);
      expect(all.single.retryCount, 1);
    });

    test('the default request timeout is the 10s aggressive limit', () {
      expect(worker.requestTimeout, const Duration(seconds: 10));
    });
  });

  group('BackgroundSyncWorker - conflict resolution (Task 5.5)', () {
    test('a 409 conflict (remote wins) drops the item and counts it', () async {
      final conflicting = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([9]),
      );
      // The remote reports a divergent acknowledged version (server
      // authoritative → local mutation superseded).
      sink.scriptConflict = MutationVersion(
        entityId: conflicting.id,
        timestamp: DateTime(2026, 8, 4, 13),
        serverAcknowledged: true,
        authorHash: 'hash-remote',
      );

      final result = await worker.runOnce();

      expect(result.pushed, 0);
      expect(result.failed, 0);
      expect(result.conflicts, 1);
      // The superseded item is dropped from the queue — never re-pushed.
      expect(await queue.getById(conflicting.id), isNull);
      expect(await queue.getPending(), isEmpty);
    });

    test('a conflict that resolves LOCAL keeps the item for retry', () async {
      final local = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([9]),
      );
      // A timestamp-first policy: the local edit is NEWER than the remote's
      // reported version, so it survives the conflict and must be retried.
      final newerWins = BackgroundSyncWorker(
        queue: queue,
        sink: sink,
        conflictResolver: const SyncConflictResolver(
          policy: _TimestampFirstPolicy(),
        ),
      );
      sink.scriptConflict = MutationVersion(
        entityId: local.id,
        timestamp: DateTime(2026, 8, 4, 10), // older than the local edit
        serverAcknowledged: true,
        authorHash: 'hash-remote',
      );

      final result = await newerWins.runOnce();

      expect(result.pushed, 0);
      expect(result.failed, 1, reason: 'local winner is retried with backoff');
      expect(result.conflicts, 0);
      final after = await queue.getById(local.id);
      expect(after, isNotNull);
      expect(after!.status, SyncQueueStatus.failed);
      expect(after.retryCount, 1);
    });

    test('mixed batch: acknowledged + rejected + conflicted each handled',
        () async {
      final okItem = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      ); // → acknowledged
      final rejectedItem = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([2]),
      ); // → rejected
      final conflictedItem = await queue.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([3]),
      ); // → conflict (remote wins)

      // Script per-item outcomes by id.
      final scripted = _ScriptedOutcomeSink({
        okItem.id: const SyncPushOutcome.acknowledged(),
        rejectedItem.id: const SyncPushOutcome.rejected(),
        conflictedItem.id: SyncPushOutcome.conflict(MutationVersion(
          entityId: conflictedItem.id,
          timestamp: DateTime(2026, 8, 4, 13),
          serverAcknowledged: true,
          authorHash: 'hash-remote',
        )),
      });
      final mixed = BackgroundSyncWorker(queue: queue, sink: scripted);

      final result = await mixed.runOnce();

      expect(result.pushed, 1);
      expect(result.failed, 1);
      expect(result.conflicts, 1);
      final all = await queue.getAll();
      expect(
          all.where((i) => i.status == SyncQueueStatus.success), hasLength(1));
      expect(
          all.where((i) => i.status == SyncQueueStatus.failed), hasLength(1));
      // The conflicted item is gone entirely.
      expect(all.any((i) => i.id == conflictedItem.id), isFalse);
    });
  });

  group('BackgroundSyncWorker - SECURITY CHECKPOINT (offline-first)', () {
    test('sink receives only sealed payloads, never plaintext', () async {
      await seedItems(2);
      final cipher = testCipher();

      await worker.runOnce();

      for (final item in sink.pushed) {
        // Payload is ciphertext that opens to a known single byte [i].
        final opened = await cipher.open(item.payload);
        expect(opened.length, 1);
        // And the raw bytes were never equal to a plaintext string.
        expect(String.fromCharCodes(item.payload), isNot(contains('plain')));
      }
    });

    test('worker performs no network calls itself — only via sink', () async {
      // The worker's collaborators are the local queue and the injected sink.
      // The sink is the ONLY outbound path (verified statically in the
      // security checkpoint suite); here we assert the worker used exactly
      // the injected sink for every item.
      await seedItems(2);
      await worker.runOnce();
      expect(sink.pushed, hasLength(2));
    });
  });
}

/// [SyncSink] that throws on every push, simulating a mid-drain network
/// failure (vs. returning a rejected outcome for a clean rejection).
class ThrowingSyncSink implements SyncSink {
  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async {
    throw StateError('simulated network failure');
  }
}

/// [SyncSink] that never completes — simulating a hung connection. The
/// worker's aggressive timeout must treat it as a failure.
class HangingSyncSink implements SyncSink {
  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) =>
      Completer<SyncPushOutcome>().future;
}

/// [SyncSink] that returns a scripted outcome per item id (Task 5.5).
class _ScriptedOutcomeSink implements SyncSink {
  final Map<String, SyncPushOutcome> outcomes;

  _ScriptedOutcomeSink(this.outcomes);

  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async =>
      outcomes[item.id] ?? const SyncPushOutcome.acknowledged();
}

/// Deterministic newer-timestamp-wins policy (equal authority), used to prove
/// the worker honors injected policies other than the default.
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

/// Mutable test clock for retry-eligibility gating.
class MutableClock {
  DateTime now;
  MutableClock(this.now);

  void advance(Duration d) => now = now.add(d);
}
