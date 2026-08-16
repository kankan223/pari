import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:civic_commons/war_room/data/aes_gcm_evidence_cipher.dart';
import 'package:civic_commons/war_room/data/queue_evidence_sink.dart';
import 'package:civic_commons/war_room/domain/evidence_envelope.dart';
import 'package:civic_commons/war_room/domain/evidence_item.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  final plaintext = Uint8List.fromList(List.generate(4096, (i) => i & 0xff));

  PickedEvidence picked({String name = 'evidence_photo.jpg'}) => PickedEvidence(
        bytes: plaintext,
        displayName: name,
        mimeType: 'image/jpeg',
        sizeBytes: plaintext.length,
      );

  group('QueueEvidenceSink (Task 8.2)', () {
    late InMemoryEntityStore<EvidenceRecord> evidenceStore;
    late InMemoryEntityStore<SyncQueueItem> queueStore;
    late LocalSyncQueueRepository syncQueue;
    late AesGcmEvidenceCipher cipher;
    late SimpleKeyPair device;
    late QueueEvidenceSink sink;
    late QueuePayloadCipher queueCipher;

    setUp(() async {
      evidenceStore = InMemoryEntityStore<EvidenceRecord>((r) => r.id);
      queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      queueCipher = testCipher();
      syncQueue =
          LocalSyncQueueRepository(store: queueStore, cipher: queueCipher);
      device = await X25519().newKeyPair();
      cipher = AesGcmEvidenceCipher(
          crypto: CryptoServiceImpl(), deviceKeyPair: device);
      sink = QueueEvidenceSink(
        cipher: cipher,
        evidenceStore: evidenceStore,
        syncQueue: syncQueue,
        recipientPublicKey: await device.extractPublicKey(),
      );
    });

    test('addEvidence writes the encrypted record AND a sealed queue item',
        () async {
      final id = await sink.addEvidence('DRAFT-x', picked());

      // 1. Local record exists — encrypted, metadata-only.
      expect(evidenceStore.length, 1);
      final record = await evidenceStore.getById(id);
      expect(record, isNotNull);
      expect(record!.caseNumber, 'DRAFT-x');
      expect(record.sizeBytes, plaintext.length);
      expect(record.mimeType, 'image/jpeg');
      expect(record.sealedFile, isNotEmpty);
      expect(record.dekEnvelope, isNotEmpty);

      // 2. A queue item exists — SEALED by the queue cipher.
      final pending = await syncQueue.getPending();
      expect(pending, hasLength(1));
      final item = pending.single;
      expect(item.operationType, SyncOperationType.create);
      expect(item.id, (await evidenceStore.getById(id))!.id,
          reason:
              'the queue item id doubles as the evidence id (idempotency key)');

      // Opening the sealed payload recovers the evidence envelope.
      final opened = await queueCipher.open(item.payload);
      final envelope = decodeEvidenceEnvelope(opened);
      expect(envelope.evidenceId, id);
      expect(envelope.sealedFile, record.sealedFile);
      expect(envelope.dekEnvelope, record.dekEnvelope);
    });

    test('BYTE-LEVEL PROOF: stored bytes never match the plaintext file',
        () async {
      await sink.addEvidence('DRAFT-x', picked());

      final record = (await evidenceStore.getAll()).single;
      expect(record.sealedFile, isNot(equals(plaintext)),
          reason: 'the sealed file must not equal the plaintext');
      // The plaintext head must not survive into the sealed blob.
      final head = plaintext.sublist(0, 64);
      expect(_contains(record.sealedFile, head), isFalse,
          reason: 'no plaintext fragment may survive into the sealed file');

      // The queue payload is sealed by the app-key cipher: raw stored bytes
      // are opaque and cannot contain the plaintext either.
      final rawPayload = (await queueStore.getAll()).single.payload;
      expect(rawPayload, isNot(equals(plaintext)));
      expect(_contains(rawPayload, head), isFalse);
    });

    test('DEK never persists in plaintext — only the wrapped envelope',
        () async {
      await sink.addEvidence('DRAFT-x', picked());
      final record = (await evidenceStore.getAll()).single;

      // The wrapped DEK decodes and is NOT the raw 32-byte key — it is
      // ciphertext under the ECDH wrap key.
      final dekEnvelope = DekEnvelope.fromBytes(record.dekEnvelope);
      expect(dekEnvelope.algorithm, DekEnvelope.alg);
      expect(dekEnvelope.wrappedDek.length, greaterThan(32));

      // Recovery path: unwrap the DEK and open the file.
      final dek = await cipher.unwrapDek(dekEnvelope, keyPair: device);
      final restored = await cipher.openFile(record.sealedFile, dek);
      expect(restored, equals(plaintext));
    });

    test('evidence record carries NO filename field (codec level)', () {
      final record = EvidenceRecord(
        id: 'id-1',
        caseNumber: 'DRAFT-x',
        sealedFile: Uint8List.fromList([1, 2, 3]),
        dekEnvelope: Uint8List.fromList([4, 5, 6]),
        sizeBytes: 3,
        mimeType: 'image/jpeg',
        createdAt: DateTime.utc(2026),
      );
      final row = evidenceRecordToRow(record);
      expect(row.containsKey('file_name'), isFalse);
      expect(row.containsKey('filename'), isFalse);
      expect(row.containsKey('path'), isFalse);
      expect(row.containsKey('display_name'), isFalse);
      expect(row.keys,
          containsAll(['id', 'case_number', 'sealed_file', 'dek_envelope']));

      // Row round-trip.
      final back = evidenceRecordFromRow(row);
      expect(back.id, record.id);
      expect(back.sealedFile, record.sealedFile);
      expect(back.dekEnvelope, record.dekEnvelope);
      expect(back.createdAt, record.createdAt);
    });

    test('localEvidence() is the cold-restart recovery snapshot', () async {
      await sink.addEvidence('DRAFT-x', picked());
      await sink.addEvidence('DRAFT-x', picked());
      final snapshot = await sink.localEvidence();
      expect(snapshot, hasLength(2));
      expect(snapshot.map((r) => r.mimeType), everyElement('image/jpeg'));
    });

    test('removeEvidence deletes the encrypted row', () async {
      final id = await sink.addEvidence('DRAFT-x', picked());
      expect(evidenceStore.length, 1);
      await sink.removeEvidence(id);
      expect(evidenceStore.length, 0);
    });

    test('failing local persist → NO partial enqueue (atomicity)', () async {
      final throwing = _ThrowingEvidenceStore();
      final failingSink = QueueEvidenceSink(
        cipher: cipher,
        evidenceStore: throwing,
        syncQueue: syncQueue,
        recipientPublicKey: await device.extractPublicKey(),
      );
      await expectLater(
          failingSink.addEvidence('DRAFT-x', picked()), throwsA(anything));
      expect(queueStore.length, 0,
          reason: 'a failed local write must never leave a queue item behind');
    });
  });
}

bool _contains(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

class _ThrowingEvidenceStore implements EntityStore<EvidenceRecord> {
  @override
  Future<void> insert(EvidenceRecord entity) async =>
      throw StateError('disk full');

  @override
  Future<void> update(EvidenceRecord entity) async {}

  @override
  Future<void> delete(String id) async {}

  @override
  Future<EvidenceRecord?> getById(String id) async => null;

  @override
  Future<List<EvidenceRecord>> getAll() async => [];
}
