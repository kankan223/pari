import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/repository/data/aes_gcm_queue_payload_cipher.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_backup.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';

import 'fakes.dart';

/// SECURITY CHECKPOINT (Task 3.3): all queued payloads are STRICTLY
/// encrypted before being stored. The store must never contain plaintext
/// mutation payloads — only ciphertext.
void main() {
  late InMemoryEntityStore<SyncQueueItem> store;
  late QueuePayloadCipher cipher;
  late LocalSyncQueueRepository repo;

  setUp(() {
    store = queueStore();
    cipher = testCipher();
    repo = LocalSyncQueueRepository(store: store, cipher: cipher);
  });

  group('SECURITY CHECKPOINT - queued payloads encrypted before storage', () {
    test('enqueue stores ciphertext, never the raw payload bytes', () async {
      final raw = Uint8List.fromList(utf8('message-plaintext-payload'));

      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: raw,
      );

      // The raw plaintext is NOT what is persisted.
      expect(item.payload, isNot(equals(raw)));
      // What IS persisted decrypts back to the original.
      final stored = await repo.getById(item.id);
      expect(stored!.payload, item.payload);
      expect(await cipher.open(stored.payload), equals(raw));
    });

    test('create() also seals — every insertion path stores ciphertext',
        () async {
      final raw = Uint8List.fromList(utf8('raw-payload'));
      final item = pendingItem('q1', payload: raw);

      final created = await repo.create(item);

      expect(created.payload, isNot(equals(raw)));
      expect(await cipher.open(created.payload), equals(raw));
    });

    test('no plaintext payload ever reaches the backing store', () async {
      final raws = <String, Uint8List>{
        'a': Uint8List.fromList(utf8('alpha-plaintext')),
        'b': Uint8List.fromList(utf8('beta-plaintext')),
        'c': Uint8List.fromList(utf8('gamma-plaintext')),
      };

      for (final entry in raws.entries) {
        await repo.enqueue(
          operationType: SyncOperationType.create,
          payload: entry.value,
        );
      }

      final stored = await store.getAll();
      expect(stored, hasLength(raws.length));
      for (final item in stored) {
        final opened = await cipher.open(item.payload);
        // Every stored payload decrypts to one of the known plaintexts.
        expect(
          raws.values.any((r) => _bytesEqual(r, opened)),
          isTrue,
          reason: 'Stored payload must decrypt to a known plaintext',
        );
        // And it must never equal any plaintext itself.
        expect(
          raws.values.any((r) => _bytesEqual(r, item.payload)),
          isFalse,
          reason: 'Store must never contain plaintext payloads',
        );
      }
    });

    test('status transitions never expose plaintext', () async {
      final raw = Uint8List.fromList(utf8('transition-payload'));
      final item = await repo.enqueue(
        operationType: SyncOperationType.update,
        payload: raw,
      );

      await repo.markInProgress(item.id);
      await repo.markFailed(item.id);

      final stored = await repo.getById(item.id);
      expect(stored!.payload, isNot(equals(raw)));
      expect(await cipher.open(stored.payload), equals(raw));
      expect(stored.retryCount, 1);
    });

    test('opening with the wrong key fails (GCM authentication)', () async {
      final wrongCipher = AesGcmQueuePayloadCipher(
        crypto: CryptoServiceImpl(),
        key: Uint8List.fromList(List.generate(32, (i) => 0xff)),
      );
      final raw = Uint8List.fromList(utf8('secret-payload'));

      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: raw,
      );

      await expectLater(
        wrongCipher.open(item.payload),
        throwsA(anything),
      );
      // And the correct cipher still recovers the payload.
      expect(await cipher.open(item.payload), equals(raw));
    });

    test('seal produces unique ciphertext per call (random nonce)', () async {
      final raw = Uint8List.fromList(utf8('same-input'));

      final a = await cipher.seal(raw);
      final b = await cipher.seal(raw);

      expect(a, isNot(equals(b)));
      expect(await cipher.open(a), equals(raw));
      expect(await cipher.open(b), equals(raw));
    });
  });

  group(
      'SECURITY CHECKPOINT - encrypted at rest across restart/backup '
      '(Task 5.6)', () {
    test('cold restart through the row codec preserves the exact sealed bytes',
        () async {
      final raw = Uint8List.fromList(utf8('restart-payload'));
      final item = await repo.enqueue(
        operationType: SyncOperationType.update,
        payload: raw,
      );

      // Simulate a restart: rows -> fresh store (exactly what a cold start
      // decodes back).
      final store2 = queueStore();
      await store2.insert(syncQueueItemFromRow(
          syncQueueItemToRow((await repo.getById(item.id))!)));

      final restarted = await store2.getById(item.id);
      // Sealed bytes are byte-identical — restart never re-encrypts.
      expect(restarted!.payload, equals(item.payload));
      // And still open to the original plaintext.
      expect(await cipher.open(restarted.payload), equals(raw));
    });

    test(
        'backup restore inserts sealed bytes as-is (never re-encrypts, '
        'never decrypts)', () async {
      final raw = Uint8List.fromList(utf8('backup-payload'));
      final item = await repo.enqueue(
        operationType: SyncOperationType.create,
        payload: raw,
      );

      final json = await SyncQueueBackup(store: store).exportQueue();
      final store2 = queueStore();
      await SyncQueueBackup(store: store2).restoreQueue(json);

      final restored = await store2.getById(item.id);
      expect(restored!.payload, equals(item.payload));
      expect(await cipher.open(restored.payload), equals(raw));
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
