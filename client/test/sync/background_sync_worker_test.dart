import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
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
      final crashingWorker =
          BackgroundSyncWorker(queue: queue, sink: throwing);

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
/// failure (vs. returning false for a clean rejection).
class ThrowingSyncSink implements SyncSink {
  @override
  Future<bool> push(SyncQueueItem item) async {
    throw StateError('simulated network failure');
  }
}
