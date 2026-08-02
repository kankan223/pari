import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_queue_repository.dart';

import 'fakes.dart';

void main() {
  late InMemoryEntityStore<SyncQueueItem> store;
  late QueuePayloadCipher cipher;
  late LocalSyncQueueRepository repo;

  setUp(() {
    store = queueStore();
    cipher = testCipher();
    repo = LocalSyncQueueRepository(store: store, cipher: cipher);
  });

  group('SyncQueueRepository - CRUD', () {
    test('create persists the item as pending', () async {
      final item = pendingItem('q1');

      final created = await repo.create(item);

      expect(created.status, SyncQueueStatus.pending);
      expect(await repo.getById('q1'), isNotNull);
      expect(store.length, 1);
    });

    test('create forces pending even when given a non-pending status',
        () async {
      final item = pendingItem('q1').copyWith(status: SyncQueueStatus.success);

      final created = await repo.create(item);

      expect(created.status, SyncQueueStatus.pending);
    });

    test('getById returns null for an unknown id', () async {
      expect(await repo.getById('missing'), isNull);
    });

    test('getAll returns every stored item', () async {
      await repo.create(pendingItem('q1'));
      await repo.create(pendingItem('q2'));

      final all = await repo.getAll();

      expect(all.map((i) => i.id), containsAll(['q1', 'q2']));
    });

    test('update persists field changes without resealing the payload',
        () async {
      await repo.create(pendingItem('q1'));
      final stored = await repo.getById('q1');
      final sealedPayload = stored!.payload;

      final updated = await repo.update(stored.copyWith(
        status: SyncQueueStatus.inProgress,
        retryCount: 2,
      ));

      final after = await repo.getById('q1');
      expect(after!.status, SyncQueueStatus.inProgress);
      expect(after.retryCount, 2);
      // Payload stays sealed — status transitions never re-encrypt.
      expect(updated.payload, sealedPayload);
    });

    test('delete removes the item', () async {
      await repo.create(pendingItem('q1'));

      await repo.delete('q1');

      expect(await repo.getById('q1'), isNull);
      expect(store.length, 0);
    });
  });

  group('SyncQueueRepository - insertion (Task 3.3)', () {
    test('enqueue persists a pending item with a fresh id', () async {
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1, 2, 3]),
      );

      expect(item.id, isNotEmpty);
      expect(item.status, SyncQueueStatus.pending);
      expect(item.retryCount, 0);
      expect(await repo.getById(item.id), isNotNull);
    });

    test('enqueue supports create/update/delete (POST/PUT/DELETE)', () async {
      for (final type in SyncOperationType.values) {
        final item = await repo.enqueue(
          operationType: type,
          payload: Uint8List.fromList([9]),
        );
        expect(item.operationType, type);
      }
    });

    test('enqueue returns the sealed payload, not the raw bytes', () async {
      final raw = Uint8List.fromList(List.generate(64, (i) => i));

      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: raw,
      );

      expect(item.payload, isNot(equals(raw)));
      // The stored payload decrypts back to the original.
      expect(await cipher.open(item.payload), equals(raw));
    });
  });

  group('SyncQueueRepository - status transitions', () {
    test('pending -> in_progress -> success', () async {
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );

      await repo.markInProgress(item.id);
      expect((await repo.getById(item.id))!.status, SyncQueueStatus.inProgress);

      await repo.markSuccess(item.id);
      expect((await repo.getById(item.id))!.status, SyncQueueStatus.success);
    });

    test('pending -> in_progress -> failed increments retryCount', () async {
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );

      await repo.markInProgress(item.id);
      await repo.markFailed(item.id);

      final stored = await repo.getById(item.id);
      expect(stored!.status, SyncQueueStatus.failed);
      expect(stored.retryCount, 1);
    });

    test('getPending returns only pending items, oldest first', () async {
      // Seed items directly so ordering is deterministic (independent of
      // wall-clock time) and includes no stray items.
      await store.insert(
        SyncQueueItem(
          id: 'old',
          operationType: SyncOperationType.create,
          payload: Uint8List(0),
          createdAt: DateTime(2026, 8, 1),
        ),
      );
      await store.insert(
        SyncQueueItem(
          id: 'fresh',
          operationType: SyncOperationType.create,
          payload: Uint8List(0),
          createdAt: DateTime(2026, 8, 2),
        ),
      );
      // A non-pending item must never be returned by getPending.
      await store.insert(
        SyncQueueItem(
          id: 'done',
          operationType: SyncOperationType.create,
          payload: Uint8List(0),
          status: SyncQueueStatus.success,
          createdAt: DateTime(2026, 8, 3),
        ),
      );

      final pending = await repo.getPending();

      // 'old' before 'fresh' (both pending); 'done' excluded.
      expect(pending.map((i) => i.id), ['old', 'fresh']);
    });

    test('markSuccess transitions the item to success', () async {
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );

      await repo.markSuccess(item.id);

      expect((await repo.getById(item.id))!.status, SyncQueueStatus.success);
    });

    test('markFailed transitions the item to failed and bumps retryCount',
        () async {
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );

      await repo.markFailed(item.id);

      final stored = await repo.getById(item.id);
      expect(stored!.status, SyncQueueStatus.failed);
      expect(stored.retryCount, 1);
    });

    test('status transitions are no-ops for unknown ids', () async {
      await repo.markInProgress('missing');
      await repo.markSuccess('missing');
      await repo.markFailed('missing');
      expect(store.length, 0);
    });
  });
}
