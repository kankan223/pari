import 'dart:typed_data';

import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/intake_draft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IntakeDraftEnvelope (Task 8.7)', () {
    IntakeDraft draft() => IntakeDraft(
          draftId: 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b',
          step: 3,
          situation: IntakeSituation.blackmailExtortion,
          narrative: 'They have my photos and want money.',
          urgency: IntakeUrgency.thisWeek,
          consentNotLegalAdvice: true,
          consentLegalAidReferral: false,
          optInAnonymizedLedger: true,
          savedAt: DateTime.utc(2026, 8, 14, 10, 30),
        );

    test('round-trips every field through the strict v:1 frame', () {
      final envelope = IntakeDraftEnvelope.fromDraft(draft());
      final decoded = IntakeDraftEnvelope.decode(envelope.encode());

      expect(decoded.draftId, 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b');
      expect(decoded.step, 3);
      expect(decoded.situation, 'blackmailExtortion');
      expect(decoded.narrative, 'They have my photos and want money.');
      expect(decoded.urgency, 'thisWeek');
      expect(decoded.consentNotLegalAdvice, isTrue);
      expect(decoded.consentLegalAidReferral, isFalse);
      expect(decoded.optInAnonymizedLedger, isTrue);
      // UTC-flag preserving (absolute instant round-trip).
      expect(decoded.savedAt, DateTime.utc(2026, 8, 14, 10, 30));
    });

    test('handles a partially-filled draft (null selections)', () {
      final d = IntakeDraft(
        draftId: 'id-1',
        step: 1,
        situation: null,
        narrative: '',
        urgency: null,
        consentNotLegalAdvice: false,
        consentLegalAidReferral: false,
        optInAnonymizedLedger: false,
        savedAt: DateTime.utc(2026, 8, 14),
      );
      final decoded =
          IntakeDraftEnvelope.decode(IntakeDraftEnvelope.fromDraft(d).encode());
      expect(decoded.situation, isNull);
      expect(decoded.urgency, isNull);
      expect(decoded.narrative, isEmpty);
      expect(decoded.step, 1);
    });

    test('rejects an unknown version', () {
      final raw = IntakeDraftEnvelope.fromDraft(draft()).encode().replaceFirst(
            '"v":1',
            '"v":99',
          );
      expect(() => IntakeDraftEnvelope.decode(raw), throwsFormatException);
    });

    test('rejects malformed frames (missing field / bad JSON / bad step)', () {
      final good = IntakeDraftEnvelope.fromDraft(draft()).encode();
      expect(
        () => IntakeDraftEnvelope.decode(good.replaceFirst(
          '"draft_id":',
          '"missing":',
        )),
        throwsFormatException,
      );
      expect(
          () => IntakeDraftEnvelope.decode('not json'), throwsFormatException);
      expect(
        () => IntakeDraftEnvelope.decode(
            good.replaceFirst('"step":3', '"step":9')),
        throwsFormatException,
      );
      expect(
        () => IntakeDraftEnvelope.decode(
            good.replaceFirst('"step":3', '"step":0')),
        throwsFormatException,
      );
    });

    test('rejects an unknown situation / urgency enum name', () {
      final good = IntakeDraftEnvelope.fromDraft(draft()).encode();
      expect(
        () => IntakeDraftEnvelope.decode(good.replaceFirst(
          '"blackmailExtortion"',
          '"notASituation"',
        )),
        throwsFormatException,
      );
      expect(
        () => IntakeDraftEnvelope.decode(
            good.replaceFirst('"thisWeek"', '"notAnUrgency"')),
        throwsFormatException,
      );
    });

    test('rejects an invalid timestamp', () {
      final good = IntakeDraftEnvelope.fromDraft(draft()).encode();
      expect(
        () => IntakeDraftEnvelope.decode(good.replaceFirst(
          '"2026-08-14T10:30:00.000Z"',
          '"not-a-date"',
        )),
        throwsFormatException,
      );
    });

    test('ZERO IDENTITY: the frame declares no phone/name/handle fields', () {
      final raw = IntakeDraftEnvelope.fromDraft(draft()).encode().toLowerCase();
      for (final shape in ['phone', 'email', 'name', 'handle', 'hash']) {
        expect(raw, isNot(contains(shape)),
            reason: 'the draft frame must never carry a $shape field');
      }
    });
  });

  group('zeroFill memory hygiene (Task 8.7)', () {
    test('overwrites every byte with zero', () {
      final bytes = Uint8List.fromList([65, 66, 67, 68, 69]);
      zeroFill(bytes);
      expect(bytes, everyElement(0));
      expect(bytes, equals(Uint8List(5)));
    });

    test('handles an empty buffer', () {
      final bytes = Uint8List(0);
      zeroFill(bytes);
      expect(bytes, isEmpty);
    });
  });
}
