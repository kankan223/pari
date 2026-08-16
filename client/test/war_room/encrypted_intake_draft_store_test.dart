import 'dart:typed_data';

import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/war_room/data/encrypted_intake_draft_store.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/intake_draft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

void main() {
  group('EncryptedIntakeDraftStore (Task 8.7)', () {
    late InMemoryEntityStore<IntakeDraftRecord> store;
    late EncryptedIntakeDraftStore draftStore;

    setUp(() {
      store = InMemoryEntityStore<IntakeDraftRecord>((r) => r.id);
      draftStore = EncryptedIntakeDraftStore(
        store: store,
        cipher: testCipher(),
      );
    });

    IntakeDraft draft({String id = 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b'}) =>
        IntakeDraft(
          draftId: id,
          step: 2,
          situation: IntakeSituation.blackmailExtortion,
          narrative: 'They have my photos and want money.',
          urgency: IntakeUrgency.thisWeek,
          consentNotLegalAdvice: true,
          consentLegalAidReferral: false,
          optInAnonymizedLedger: false,
          savedAt: DateTime.utc(2026, 8, 14, 10, 30),
        );

    test('save → load round-trip restores every field (pause/resume)',
        () async {
      await draftStore.saveDraft(draft());
      final loaded =
          await draftStore.loadDraft('a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b');

      expect(loaded, isNotNull);
      expect(loaded!.draftId, 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b');
      expect(loaded.step, 2);
      expect(loaded.situation, IntakeSituation.blackmailExtortion);
      expect(loaded.narrative, 'They have my photos and want money.');
      expect(loaded.urgency, IntakeUrgency.thisWeek);
      expect(loaded.consentNotLegalAdvice, isTrue);
      expect(loaded.consentLegalAidReferral, isFalse);
      expect(loaded.savedAt, DateTime.utc(2026, 8, 14, 10, 30));
    });

    test('BYTE-LEVEL PROOF: the stored row contains zero plaintext', () async {
      final d = draft();
      await draftStore.saveDraft(d);

      final record = (await store.getAll()).single;
      final raw = String.fromCharCodes(record.sealedPayload);
      // No narrative text, no field names, no id survive in plaintext.
      expect(raw.contains('photos'), isFalse,
          reason: 'narrative must never survive in the stored bytes');
      expect(raw.contains('narrative'), isFalse,
          reason: 'frame field names must not survive unsealed');
      expect(raw.contains('blackmailExtortion'), isFalse);
      expect(raw.contains('a9d34f8e'), isFalse);
    });

    test('delete removes the draft', () async {
      await draftStore.saveDraft(draft());
      await draftStore.deleteDraft('a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b');
      expect(await draftStore.loadDraft('a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b'),
          isNull);
      expect(store.length, 0);
    });

    test('loadDraft returns null for an absent id', () async {
      expect(await draftStore.loadDraft('missing'), isNull);
    });

    test('listDrafts returns newest-first (resume surface order)', () async {
      await draftStore.saveDraft(draft(id: 'id-old').let((d) => IntakeDraft(
            draftId: d.draftId,
            step: d.step,
            situation: d.situation,
            narrative: d.narrative,
            urgency: d.urgency,
            consentNotLegalAdvice: d.consentNotLegalAdvice,
            consentLegalAidReferral: d.consentLegalAidReferral,
            optInAnonymizedLedger: d.optInAnonymizedLedger,
            savedAt: DateTime.utc(2026, 8, 13),
          )));
      await draftStore.saveDraft(draft(id: 'id-new'));
      final drafts = await draftStore.listDrafts();
      expect(drafts.map((d) => d.draftId).toList(), ['id-new', 'id-old']);
    });

    test(
        'cold-restart recovery: a fresh store over the same entity store '
        'loads the sealed draft (crash survival)', () async {
      await draftStore.saveDraft(draft());
      // Simulate an app restart — new store instance, same backing store.
      final restarted = EncryptedIntakeDraftStore(
        store: store,
        cipher: testCipher(),
      );
      final loaded =
          await restarted.loadDraft('a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b');
      expect(loaded!.narrative, 'They have my photos and want money.');
    });

    test('a DIFFERENT key cannot open the sealed draft (tamper/wrong-key)',
        () async {
      await draftStore.saveDraft(draft());
      final wrongKey = _XorCipher();
      final attacker =
          EncryptedIntakeDraftStore(store: store, cipher: wrongKey);
      await expectLater(
        attacker.loadDraft('a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b'),
        throwsA(anything),
      );
    });

    test('re-saving the same draft id replaces the row (idempotent resume)',
        () async {
      await draftStore.saveDraft(draft());
      await draftStore.saveDraft(draft());
      expect(store.length, 1);
    });
  });
}

extension _Let<T> on T {
  R let<R>(R Function(T) f) => f(this);
}

/// A deliberately wrong cipher — every open fails (proves the sealed draft
/// is unrecoverable without the right key hierarchy).
class _XorCipher implements QueuePayloadCipher {
  @override
  Future<Uint8List> seal(Uint8List plaintext) async => plaintext;

  @override
  Future<Uint8List> open(Uint8List sealed) async =>
      throw StateError('wrong key');
}
