import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_backup.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';

import 'fakes.dart';

/// VERIFY (Task 5.6): queue backup/restore — the portable envelope round-trips
/// every queued mutation byte-for-byte (sealed payloads as-is), strict
/// validation rejects corrupt backups atomically, and the SECURITY CHECKPOINT
/// holds: raw plaintext never appears in an exported backup.
void main() {
  group('SyncQueueBackup - export envelope (Task 5.6)', () {
    test('exports items oldest-first in a version 1 envelope', () async {
      final store = queueStore();
      final backup = SyncQueueBackup(store: store);
      await store.insert(SyncQueueItem(
        id: 'newer',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 2),
      ));
      await store.insert(SyncQueueItem(
        id: 'older',
        operationType: SyncOperationType.create,
        payload: Uint8List(0),
        createdAt: DateTime(2026, 8, 1),
      ));

      final json =
          await backup.exportQueue(exportedAt: DateTime(2026, 8, 3, 12));

      final decoded = jsonDecode(json) as Map<String, dynamic>;
      expect(decoded['version'], syncQueueBackupVersion);
      expect(decoded['exportedAt'],
          DateTime(2026, 8, 3, 12).microsecondsSinceEpoch);
      final items = decoded['items'] as List;
      expect(items.map((i) => (i as Map)['id']), ['older', 'newer']);
    });
  });

  group('SyncQueueBackup - round-trip (Task 5.6)', () {
    test('export -> restore into a fresh store is byte-exact', () async {
      final cipher = testCipher();
      final storeA = queueStore();
      final repoA = LocalSyncQueueRepository(store: storeA, cipher: cipher);
      final a = await repoA.enqueue(
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList(utf8('alpha')),
      );
      final b = await repoA.enqueue(
        operationType: SyncOperationType.update,
        payload: Uint8List.fromList(utf8('beta')),
      );
      await repoA.markInProgress(b.id);
      await repoA.markFailed(b.id); // realistic retry metadata

      final json = await SyncQueueBackup(store: storeA).exportQueue();

      // "Move to a fresh install": restore into a brand-new store.
      final storeB = queueStore();
      final restoredCount =
          await SyncQueueBackup(store: storeB).restoreQueue(json);
      expect(restoredCount, 2);

      final restoredA = await storeB.getById(a.id);
      final restoredB = await storeB.getById(b.id);
      expect(restoredA!.payload, equals(a.payload)); // sealed bytes identical
      expect(restoredB!.payload, equals(b.payload));
      expect(restoredB.status, SyncQueueStatus.failed);
      expect(restoredB.retryCount, 1);
      expect(restoredA.createdAt, a.createdAt);
      expect(restoredA.lastAttemptAt, a.lastAttemptAt);
      // The same key still opens the restored sealed payloads.
      expect(await cipher.open(restoredA.payload), equals(utf8('alpha')));
      expect(await cipher.open(restoredB.payload), equals(utf8('beta')));
    });
  });
  test('restoring the same backup twice never duplicates items', () async {
    final store = queueStore();
    final backup = SyncQueueBackup(store: store);
    final good = serializeQueueBackup([pendingItem('q1'), pendingItem('q2')]);

    final first = await backup.restoreQueue(good);
    final second = await backup.restoreQueue(good);

    expect(first, 2);
    expect(second, 0,
        reason: 'a re-restore of an already-present backup is a no-op');
    expect(store.length, 2,
        reason: 'restore must be idempotent — no duplicate mutations');
    expect(await store.getById('q1'), isNotNull);
    expect(await store.getById('q2'), isNotNull);
  });
  group('SyncQueueBackup - strict validation (Task 5.6)', () {
    test('unknown version is rejected', () {
      expect(
        () => deserializeQueueBackup('{"version": 99, "items": []}'),
        throwsFormatException,
      );
    });

    test('unknown operationType is rejected', () {
      final tampered = _withFirstItemPatched('operationType', 'patch');
      expect(() => deserializeQueueBackup(tampered), throwsFormatException);
    });

    test('unknown status is rejected', () {
      final tampered = _withFirstItemPatched('status', 'queued');
      expect(() => deserializeQueueBackup(tampered), throwsFormatException);
    });

    test('invalid base64 payload is rejected', () {
      // 'A' is one base64 char (invalid length 1 mod 4) — guaranteed to throw.
      final tampered = _withFirstItemPatched('payload', 'A');
      expect(() => deserializeQueueBackup(tampered), throwsFormatException);
    });

    test('malformed JSON / non-object envelope / non-list items are rejected',
        () {
      expect(() => deserializeQueueBackup('not json at all'),
          throwsFormatException);
      expect(() => deserializeQueueBackup('[1, 2, 3]'), throwsFormatException);
      expect(() => deserializeQueueBackup('{"version": 1, "items": [42]}'),
          throwsFormatException);
    });

    test('a corrupt backup never partially restores', () async {
      final store = queueStore();
      final backup = SyncQueueBackup(store: store);
      // Valid two-item backup restores cleanly.
      final good = serializeQueueBackup([pendingItem('q1'), pendingItem('q2')]);
      expect(await backup.restoreQueue(good), 2);
      expect(store.length, 2);

      // A corrupt envelope (one bad item) throws BEFORE any insert — the
      // queue is untouched.
      final corrupt = _withFirstItemPatched('operationType', 'patch');
      await expectLater(backup.restoreQueue(corrupt), throwsFormatException);
      expect(store.length, 2,
          reason: 'a failed restore must not partially mutate the queue');
    });
  });

  group('SyncQueueBackup - SECURITY CHECKPOINT (Task 5.6)', () {
    test('the exported envelope never contains raw plaintext payloads',
        () async {
      final cipher = testCipher();
      final store = queueStore();
      final repo = LocalSyncQueueRepository(store: store, cipher: cipher);
      const secrets = ['super-secret-alpha', 'super-secret-beta'];
      for (final s in secrets) {
        await repo.enqueue(
          operationType: SyncOperationType.create,
          payload: Uint8List.fromList(utf8(s)),
        );
      }

      final json = await SyncQueueBackup(store: store).exportQueue();

      // The raw plaintext strings never appear anywhere in the envelope.
      for (final s in secrets) {
        expect(json.contains(s), isFalse,
            reason: 'raw mutation plaintext must never appear in a backup');
      }
      // Payloads are base64 of ciphertext only.
      final decoded = jsonDecode(json) as Map<String, dynamic>;
      for (final raw in decoded['items'] as List) {
        final payloadB64 = (raw as Map)['payload'] as String;
        final bytes = base64Decode(payloadB64);
        for (final s in secrets) {
          expect(String.fromCharCodes(bytes).contains(s), isFalse);
        }
      }
    });
  });
}

// --- helpers: robust envelope tampering (decode -> modify -> re-encode) -----

/// Re-encodes a single-item envelope with [key] on the first item set to
/// [value] (decode -> mutate -> re-encode, so the tampering is independent
/// of jsonEncode's exact whitespace).
String _withFirstItemPatched(String key, Object? value) {
  final decoded = jsonDecode(serializeQueueBackup([pendingItem('q1')]))
      as Map<String, dynamic>;
  final items = decoded['items'] as List;
  final first = (items[0] as Map<String, dynamic>);
  items[0] = {...first, key: value};
  return jsonEncode(decoded);
}
