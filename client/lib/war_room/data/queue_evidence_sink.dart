import 'package:cryptography/cryptography.dart';

import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/evidence_envelope.dart';
import '../domain/evidence_item.dart';
import '../domain/evidence_ports.dart';

/// Production [EvidenceSink] (data layer, Task 8.2 Encrypted Evidence
/// Upload).
///
/// The offline-first write order for every evidence item:
/// 1. **Encrypt FIRST** — a fresh 32-byte DEK seals the file bytes
///    (AES-256-GCM) and is itself wrapped to the recipient public key
///    (X25519 ECDH). No plaintext file ever reaches the store or queue.
/// 2. **Local-first persist** — the [EvidenceRecord] (metadata + sealed
///    file + wrapped DEK) is written to the encrypted local [EntityStore]
///    (`evidence` table) IMMEDIATELY.
/// 3. **Sealed enqueue** — the [EvidenceEnvelope] is enqueued; the
///    [SyncQueueRepository] seals it with the app-key AES-256-GCM queue
///    cipher BEFORE storage. The item id doubles as the Idempotency-Key.
///
/// SECURITY CHECKPOINT (Task 8.2): the evidence row contains NO filename,
/// NO path, NO EXIF, NO identity — only non-sensitive metadata + opaque
/// ciphertext. The queue never persists a plaintext byte of the file, and
/// the DEK never exists outside the wrapped envelope.
class QueueEvidenceSink implements EvidenceSink {
  final EvidenceCipher _cipher;
  final EntityStore<EvidenceRecord> _evidenceStore;
  final SyncQueueRepository _syncQueue;
  final SimplePublicKey _recipientPublicKey;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  QueueEvidenceSink({
    required EvidenceCipher cipher,
    required EntityStore<EvidenceRecord> evidenceStore,
    required SyncQueueRepository syncQueue,
    required SimplePublicKey recipientPublicKey,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _cipher = cipher,
        _evidenceStore = evidenceStore,
        _syncQueue = syncQueue,
        _recipientPublicKey = recipientPublicKey,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<EvidenceRecord>> localEvidence() => _evidenceStore.getAll();

  @override
  Future<void> removeEvidence(String evidenceId) async {
    await _evidenceStore.delete(evidenceId);
  }

  @override
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence) async {
    // 1. Encrypt BEFORE any persistence: seal the file under a fresh DEK
    //    and wrap the DEK to the recipient key.
    final dek = await _cipher.generateDek();
    final sealedFile = await _cipher.sealFile(evidence.bytes, dek);
    final dekEnvelope = await _cipher.wrapDek(
      dek,
      recipient: _recipientPublicKey,
    );
    // Wipe the plaintext DEK from memory — only the wrapped form survives.
    dek.fillRange(0, dek.length, 0);

    final id = _idGen.generate();
    // 2. Local-first write — the encrypted record lands immediately.
    await _evidenceStore.insert(
      EvidenceRecord(
        id: id,
        caseNumber: caseNumber,
        sealedFile: sealedFile,
        dekEnvelope: dekEnvelope.toBytes(),
        sizeBytes: evidence.sizeBytes,
        mimeType: evidence.mimeType,
        createdAt: _clock(),
      ),
    );
    // 3. Queue the mutation — the envelope carries ONLY the sealed file +
    //    wrapped DEK + non-sensitive metadata, and the queue repository
    //    seals the frame with the app-key cipher before storage. The item
    //    is created with [id] as its item id so the idempotency key travels
    //    with the mutation (enqueue() would mint a fresh id).
    final envelope = EvidenceEnvelope(
      evidenceId: id,
      caseNumber: caseNumber,
      sizeBytes: evidence.sizeBytes,
      mimeType: evidence.mimeType,
      createdAt: _clock(),
      sealedFile: sealedFile,
      dekEnvelope: dekEnvelope.toBytes(),
    );
    await _syncQueue.create(
      SyncQueueItem(
        id: id,
        operationType: SyncOperationType.create,
        payload: encodeEvidenceEnvelope(envelope),
        createdAt: _clock(),
      ),
    );
    return id;
  }
}
