import 'dart:convert';
import 'dart:typed_data';

import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/custody_log.dart';

/// Production [LegalAidHandoffSink] (Task 8.6 — legal-aid handoff webhook
/// integration).
///
/// Offline-first write order, mirroring the evidence sink:
/// 1. **Local-first persist** — the handoff (case stamp + report signature
///    reference + blinded analyst + timestamp) is written to the encrypted
///    local store IMMEDIATELY.
/// 2. **Sealed enqueue** — the strict `v:1` [LegalAidHandoffEnvelope] is
///    enqueued via [SyncQueueRepository.create] with the handoff id as the
///    item id (doubles as the Idempotency-Key — `enqueue()` would mint a
///    fresh id). The queue repository seals the payload with the app-key
///    AES-256-GCM cipher BEFORE storage.
///
/// SECURITY CHECKPOINT (8.6): the frame carries ONLY the case stamp, the
/// report signature reference, a blinded analyst handle, and a timestamp —
/// ZERO identity, ZERO report content. The queue never persists plaintext.
class QueueLegalAidHandoffSink implements LegalAidHandoffSink {
  final EntityStore<LegalAidHandoff> _handoffStore;
  final SyncQueueRepository _syncQueue;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  QueueLegalAidHandoffSink({
    required EntityStore<LegalAidHandoff> handoffStore,
    required SyncQueueRepository syncQueue,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _handoffStore = handoffStore,
        _syncQueue = syncQueue,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<LegalAidHandoff>> localHandoffs() => _handoffStore.getAll();

  @override
  Future<String> queue(LegalAidHandoff handoff) async {
    // The handoff id is the UUID v4 idempotency key (minted here when the
    // caller did not pre-assign one — e.g. the repository hands a draft).
    final id = handoff.id.isEmpty ? _idGen.generate() : handoff.id;
    final resolved = LegalAidHandoff(
      id: id,
      caseNumber: handoff.caseNumber,
      reportSignature: handoff.reportSignature,
      analystId: handoff.analystId,
      queuedAt: handoff.queuedAt,
    );
    // 1. Local-first — the handoff lands in the encrypted store immediately.
    await _handoffStore.insert(resolved);
    // 2. Sealed enqueue — the strict frame, item id = handoff id (idempotency).
    final envelope = LegalAidHandoffEnvelope.fromHandoff(resolved);
    final payload = Uint8List.fromList(utf8.encode(envelope.encode()));
    await _syncQueue.create(
      SyncQueueItem(
        id: id,
        operationType: SyncOperationType.create,
        payload: payload,
        createdAt: _clock(),
      ),
    );
    return id;
  }
}
