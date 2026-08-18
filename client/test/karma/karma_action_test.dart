import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaAction — PRD §9.2 action values', () {
    test('every PRD action exists with the documented delta and pillar', () {
      expect(KarmaAction.ledgerPostVerified.delta, 5);
      expect(KarmaAction.ledgerPostVerified.pillar, KarmaPillar.ledger);
      expect(KarmaAction.warRoomCaseContribution.delta, 15);
      expect(KarmaAction.warRoomCaseContribution.pillar, KarmaPillar.warRoom);
      expect(KarmaAction.sandboxNoteUpvoted3.delta, 3);
      expect(KarmaAction.sandboxNoteUpvoted3.pillar, KarmaPillar.academy);
      expect(KarmaAction.academyModuleCompleted.delta, 2);
      expect(KarmaAction.academyModuleCompleted.pillar, KarmaPillar.academy);
      expect(KarmaAction.warRoomAnalystVetted.delta, 20);
      expect(KarmaAction.warRoomAnalystVetted.pillar, KarmaPillar.warRoom);
      expect(KarmaAction.ledgerPostRejected.delta, -3);
      expect(KarmaAction.ledgerPostRejected.pillar, KarmaPillar.ledger);
      expect(KarmaAction.confirmedAbuseReport.delta, -25);
      expect(KarmaAction.confirmedAbuseReport.pillar, KarmaPillar.crossPillar);
    });

    test('analyst vetting is the only one-time action', () {
      expect(KarmaAction.warRoomAnalystVetted.oneTime, isTrue);
      for (final action in KarmaAction.values) {
        if (action != KarmaAction.warRoomAnalystVetted) {
          expect(action.oneTime, isFalse,
              reason: '${action.wireName} must not be one-time');
        }
      }
    });

    test('every action carries a fixed non-empty label (UI-safe text)', () {
      for (final action in KarmaAction.values) {
        expect(action.label.trim(), isNotEmpty);
        expect(action.label, isNot(contains('\n')));
      }
    });
  });

  group('KarmaAction — strict wire decode', () {
    test('wire round-trip is identity for every action', () {
      for (final action in KarmaAction.values) {
        expect(KarmaAction.fromWireName(action.wireName), action);
      }
    });

    test('unknown wire names throw (forged rows cannot masquerade)', () {
      expect(() => KarmaAction.fromWireName('ledger_post_verified'),
          returnsNormally);
      expect(() => KarmaAction.fromWireName(''), throwsArgumentError);
      expect(
          () => KarmaAction.fromWireName('not_an_action'), throwsArgumentError);
      expect(() => KarmaAction.fromWireName('ledgerPostVerified'),
          throwsArgumentError);
    });
  });

  group('KarmaPillar — strict wire decode', () {
    test('wire round-trip is identity for every pillar', () {
      for (final pillar in KarmaPillar.values) {
        expect(KarmaPillar.fromWireName(pillar.wireName), pillar);
      }
    });

    test('unknown pillars throw', () {
      expect(() => KarmaPillar.fromWireName(''), throwsArgumentError);
      expect(() => KarmaPillar.fromWireName('vault'), throwsArgumentError);
    });
  });
}
