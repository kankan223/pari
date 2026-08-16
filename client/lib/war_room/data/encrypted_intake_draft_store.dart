import 'dart:convert';
import 'dart:typed_data';

import '../../repository/domain/entity_store.dart';
import '../../repository/domain/queue_payload_cipher.dart';
import '../domain/case_intake.dart';
import '../domain/intake_draft.dart';

/// The durable, locally persisted row for a paused intake draft (Task 8.7).
///
/// SECURITY CHECKPOINT (8.7): the row carries ONLY the draft id + the
/// AES-256-GCM SEALED envelope + the saved timestamp. The plaintext
/// narrative (case content) never touches the store — [sealedPayload] is
/// opaque ciphertext by construction.
class IntakeDraftRecord {
  /// UUID v4 draft id.
  final String id;

  /// AES-256-GCM sealed [IntakeDraftEnvelope] frame.
  final Uint8List sealedPayload;

  final DateTime savedAt;

  const IntakeDraftRecord({
    required this.id,
    required this.sealedPayload,
    required this.savedAt,
  });
}

/// Production [IntakeDraftStore] (data layer, Task 8.7 Pause, Save &
/// Resume).
///
/// Write path (offline-first, encrypted at rest):
/// 1. **Seal FIRST** — the strict `v:1` draft envelope is sealed with the
///    app-key AES-256-GCM cipher BEFORE any persistence.
/// 2. **Local-first persist** — the [IntakeDraftRecord] (id + sealed
///    payload + timestamp) is written to the encrypted local
///    [EntityStore] (`intake_drafts` table) IMMEDIATELY.
///
/// Read path recovers the plaintext draft ONLY inside the local app (the
/// cipher's [QueuePayloadCipher.open] — never on the network).
///
/// SECURITY CHECKPOINT (8.7): the raw store bytes never match the plaintext
/// envelope; a draft is recoverable only through the device key hierarchy.
class EncryptedIntakeDraftStore implements IntakeDraftStore {
  final EntityStore<IntakeDraftRecord> _store;
  final QueuePayloadCipher _cipher;

  EncryptedIntakeDraftStore({
    required EntityStore<IntakeDraftRecord> store,
    required QueuePayloadCipher cipher,
  })  : _store = store,
        _cipher = cipher;

  @override
  Future<void> saveDraft(IntakeDraft draft) async {
    // Seal BEFORE persistence — the plaintext frame never touches the store.
    final envelope = IntakeDraftEnvelope.fromDraft(draft);
    final frame = Uint8List.fromList(utf8.encode(envelope.encode()));
    final sealed = await _cipher.seal(frame);
    // Zero the transient plaintext frame once sealed (memory hygiene).
    zeroFill(frame);
    await _store.insert(IntakeDraftRecord(
      id: draft.draftId,
      sealedPayload: sealed,
      savedAt: draft.savedAt,
    ));
  }

  @override
  Future<IntakeDraft?> loadDraft(String draftId) async {
    final record = await _store.getById(draftId);
    if (record == null) {
      return null;
    }
    return _open(record);
  }

  @override
  Future<void> deleteDraft(String draftId) async {
    await _store.delete(draftId);
  }

  @override
  Future<List<IntakeDraft>> listDrafts() async {
    final records = await _store.getAll();
    final drafts = <IntakeDraft>[];
    for (final record in records) {
      drafts.add(await _open(record));
    }
    // Newest saved first — the most recent pause is the resume surface.
    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  /// Opens the sealed record back into a domain draft (local-only — throws
  /// on tamper / wrong key).
  Future<IntakeDraft> _open(IntakeDraftRecord record) async {
    final plain = await _cipher.open(record.sealedPayload);
    final envelope = IntakeDraftEnvelope.decode(String.fromCharCodes(plain));
    // Zero the transient opened frame (memory hygiene).
    plain.fillRange(0, plain.length, 0);
    return IntakeDraft(
      draftId: envelope.draftId,
      step: envelope.step,
      situation: envelope.situation == null
          ? null
          : IntakeSituation.values.byName(envelope.situation!),
      narrative: envelope.narrative,
      urgency: envelope.urgency == null
          ? null
          : IntakeUrgency.values.byName(envelope.urgency!),
      consentNotLegalAdvice: envelope.consentNotLegalAdvice,
      consentLegalAidReferral: envelope.consentLegalAidReferral,
      optInAnonymizedLedger: envelope.optInAnonymizedLedger,
      savedAt: envelope.savedAt,
    );
  }
}
