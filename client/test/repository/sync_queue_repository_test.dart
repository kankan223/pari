import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';

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

    test('enqueue ids are UUID v4 idempotency keys (Task 5.2)', () async {
      final keyRegex = RegExp(
        r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
      );
      final a = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );
      final b = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([2]),
      );

      expect(a.id, matches(keyRegex));
      expect(b.id, matches(keyRegex));
      expect(a.id, isNot(b.id));
      // The queue id doubles as the transport Idempotency-Key: unique per
      // mutation so retries dedupe server-side.
      expect(a.id, isNotEmpty);
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

  group('SyncQueueRepository - size cap & FIFO eviction (Task 5.6)', () {
    test('the production cap is exactly 1000 items', () {
      expect(LocalSyncQueueRepository.defaultMaxQueueSize, 1000);
    });

    test('enqueue beyond the cap evicts the OLDEST items (FIFO)', () async {
      final cappedStore = queueStore();
      final capped = LocalSyncQueueRepository(
        store: cappedStore,
        cipher: cipher,
        maxQueueSize: 3,
      );
      // Seed two old items with distinct ages for a deterministic eviction.
      await cappedStore.insert(SyncQueueItem(
        id: 'oldest',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 1),
      ));
      await cappedStore.insert(SyncQueueItem(
        id: 'older',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 2),
      ));

      // Two more inserts push the total to 4 > 3 → exactly 1 eviction, and it
      // must be the oldest ('oldest'), never the just-inserted item.
      final a = await capped.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([3]),
      );
      final b = await capped.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([4]),
      );

      final remaining = await cappedStore.getAll();
      expect(remaining, hasLength(3));
      expect(remaining.map((i) => i.id), containsAll(['older', a.id, b.id]));
      expect(await cappedStore.getById('oldest'), isNull);
    });

    test('in-flight items are NEVER evicted (oldest non-flight goes first)',
        () async {
      final cappedStore = queueStore();
      final capped = LocalSyncQueueRepository(
        store: cappedStore,
        cipher: cipher,
        maxQueueSize: 2,
      );
      // The in_progress item is the OLDEST — it would be the first candidate
      // under a naive FIFO, but it must be protected.
      await cappedStore.insert(SyncQueueItem(
        id: 'flight',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        status: SyncQueueStatus.inProgress,
        createdAt: DateTime(2026, 8, 1),
      ));
      await cappedStore.insert(SyncQueueItem(
        id: 'old',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 2),
      ));

      final newest = await capped.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([9]),
      );

      final remaining = await cappedStore.getAll();
      expect(remaining.map((i) => i.id), containsAll(['flight', newest.id]));
      expect(await cappedStore.getById('old'), isNull);
    });

    test('the queue is untouched while under the cap', () async {
      final cappedStore = queueStore();
      final capped = LocalSyncQueueRepository(
        store: cappedStore,
        cipher: cipher,
        maxQueueSize: 5,
      );

      await capped.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1]),
      );

      expect(await cappedStore.getAll(), hasLength(1));
    });

    test('eviction never corrupts the sealed payloads of survivors', () async {
      final cappedStore = queueStore();
      final capped = LocalSyncQueueRepository(
        store: cappedStore,
        cipher: cipher,
        maxQueueSize: 2,
      );
      final raws = [
        Uint8List.fromList(utf8('alpha-plaintext')),
        Uint8List.fromList(utf8('beta-plaintext')),
        Uint8List.fromList(utf8('gamma-plaintext')),
      ];

      for (final raw in raws) {
        await capped.enqueue(
          operationType: SyncOperationType.create,
          payload: raw,
        );
      }

      final remaining = await cappedStore.getAll();
      expect(remaining, hasLength(2));
      for (final item in remaining) {
        // Every surviving sealed payload still opens to a known plaintext
        // (eviction deletes rows, it never touches ciphertext).
        final opened = await cipher.open(item.payload);
        expect(
          raws.any((r) => _bytesEqual(r, opened)),
          isTrue,
          reason: 'survivor payload must decrypt to a known plaintext',
        );
      }
    });

    test('the just-inserted item survives even on createdAt ties', () async {
      final cappedStore = queueStore();
      // Fixed clock: EVERY enqueue shares the same createdAt, so a naive
      // createdAt sort cannot decide which item is newest — the cap must
      // guarantee survival by construction, not by sort order.
      final tied = DateTime(2026, 8, 1, 12);
      final capped = LocalSyncQueueRepository(
        store: cappedStore,
        cipher: cipher,
        maxQueueSize: 2,
        clock: () => tied,
      );
      await cappedStore.insert(SyncQueueItem(
        id: 's1',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: tied,
      ));
      await cappedStore.insert(SyncQueueItem(
        id: 's2',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: tied,
      ));

      final newest = await capped.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([9]),
      );

      final remaining = await cappedStore.getAll();
      expect(remaining, hasLength(2));
      expect(remaining.map((i) => i.id), contains(newest.id),
          reason: 'the item that triggered the cap must never be evicted');
    });
  });

  group('SyncQueueRepository - purgeExpired 30-day retention (Task 5.6)', () {
    test('purges items older than 30 days and returns the count', () async {
      await store.insert(SyncQueueItem(
        id: 'stale',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 7, 1),
      ));
      await store.insert(SyncQueueItem(
        id: 'fresh',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 1),
      ));

      final purged = await repo.purgeExpired(now: DateTime(2026, 8, 1, 12));

      expect(purged, 1);
      expect(await store.getById('stale'), isNull);
      expect(await store.getById('fresh'), isNotNull);
    });

    test('an item exactly maxAge old survives (strictly-older boundary)',
        () async {
      final now = DateTime(2026, 8, 1, 12);
      await store.insert(SyncQueueItem(
        id: 'exact',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: now.subtract(const Duration(days: 30)),
      ));

      final purged = await repo.purgeExpired(now: now);

      expect(purged, 0);
      expect(await store.getById('exact'), isNotNull);
    });

    test('purges across ALL statuses, including in_progress leftovers',
        () async {
      final old = DateTime(2026, 1, 1);
      for (final status in SyncQueueStatus.values) {
        await store.insert(SyncQueueItem(
          id: 'stale-${status.name}',
          operationType: SyncOperationType.create,
          payload: Uint8List(0),
          status: status,
          createdAt: old,
        ));
      }

      final purged = await repo.purgeExpired(now: DateTime(2026, 8, 1, 12));

      expect(purged, SyncQueueStatus.values.length);
      expect(await store.getAll(), isEmpty);
    });

    test('defaults: 30-day maxAge and the repository clock supply now',
        () async {
      final now = DateTime(2026, 8, 1, 12);
      final clockRepo = LocalSyncQueueRepository(
        store: store,
        cipher: cipher,
        clock: () => now,
      );
      await store.insert(SyncQueueItem(
        id: 'stale',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 6, 1),
      ));

      final purged = await clockRepo.purgeExpired();

      expect(purged, 1);
      expect(await store.getById('stale'), isNull);
    });
  });

  group('SyncQueueRepository - exact serialization bounds (Task 5.6)', () {
    test('row codec round-trips every field exactly (payload, status, times)',
        () async {
      final micro = DateTime(2026, 8, 1, 12, 30, 45, 123, 456);
      final item = SyncQueueItem(
        id: 'q1',
        operationType: SyncOperationType.update,
        payload: Uint8List.fromList(List.generate(256, (i) => i)),
        status: SyncQueueStatus.failed,
        retryCount: 3,
        createdAt: micro,
        lastAttemptAt: micro.add(const Duration(microseconds: 42)),
      );

      final restored = syncQueueItemFromRow(syncQueueItemToRow(item));

      expect(restored.id, item.id);
      expect(restored.operationType, item.operationType);
      expect(restored.payload, equals(item.payload)); // byte-exact
      expect(restored.status, item.status);
      expect(restored.retryCount, item.retryCount);
      expect(restored.createdAt, item.createdAt); // microsecond-exact
      expect(restored.lastAttemptAt, item.lastAttemptAt);
    });

    test('null lastAttemptAt survives (never-attempted is preserved)',
        () async {
      final restored =
          syncQueueItemFromRow(syncQueueItemToRow(pendingItem('q1')));
      expect(restored.lastAttemptAt, isNull);
      expect(restored.retryCount, 0);
      expect(restored.status, SyncQueueStatus.pending);
    });

    test('sub-millisecond timestamps survive the row codec', () async {
      final t = DateTime.fromMicrosecondsSinceEpoch(1785999000123456);

      final restored = syncQueueItemFromRow(syncQueueItemToRow(
        SyncQueueItem(
          id: 'q',
          operationType: SyncOperationType.create,
          payload: Uint8List(0),
          createdAt: t,
        ),
      ));

      expect(restored.createdAt, t);
      expect(restored.createdAt.microsecond, t.microsecond);
    });

    test('large sealed payloads round-trip byte-exact', () async {
      final big = Uint8List.fromList(List.generate(65536, (i) => i % 251));

      final restored = syncQueueItemFromRow(syncQueueItemToRow(
        SyncQueueItem(
          id: 'q',
          operationType: SyncOperationType.delete,
          payload: big,
          createdAt: DateTime(2026, 8, 1),
        ),
      ));

      expect(restored.payload, equals(big));
    });

    test('unknown status/operation in a row throws (strict bounds)', () {
      final good = syncQueueItemToRow(pendingItem('q1'));
      expect(
        () => syncQueueItemFromRow({...good, 'status': 'bogus'}),
        throwsArgumentError,
      );
      expect(
        () => syncQueueItemFromRow({...good, 'operation_type': 'PATCH'}),
        throwsArgumentError,
      );
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
