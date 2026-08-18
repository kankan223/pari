import 'package:civic_commons/karma/domain/karma_gate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('KarmaGate — PRD §9.2 thresholds', () {
    test('every gate carries its documented threshold', () {
      expect(KarmaGate.skipProbationPosting.threshold, 50);
      expect(KarmaGate.peerReviewVoting.threshold, 100);
      expect(KarmaGate.warRoomAnalystEligibility.threshold, 150);
      expect(KarmaGate.moderatorCouncil.threshold, 500);
    });

    test('only the Moderator Council requires tenure', () {
      expect(KarmaGate.moderatorCouncil.tenureDays, 90);
      for (final gate in KarmaGate.values) {
        if (gate != KarmaGate.moderatorCouncil) {
          expect(gate.tenureDays, isNull);
        }
      }
    });
  });

  group('KarmaGate.isSatisfied', () {
    test('score-only gates ignore tenure', () {
      expect(
        KarmaGate.skipProbationPosting
            .isSatisfied(karma: 50, accountAgeDays: 0),
        isTrue,
      );
      expect(
        KarmaGate.skipProbationPosting
            .isSatisfied(karma: 49, accountAgeDays: 400),
        isFalse,
      );
    });

    test('boundary: exactly at threshold is satisfied', () {
      for (final gate in KarmaGate.values) {
        expect(
          gate.isSatisfied(karma: gate.threshold, accountAgeDays: 999),
          isTrue,
          reason: gate.wireName,
        );
      }
    });

    test('Moderator Council requires score AND 90-day tenure', () {
      expect(
        KarmaGate.moderatorCouncil.isSatisfied(karma: 500, accountAgeDays: 90),
        isTrue,
      );
      expect(
        KarmaGate.moderatorCouncil.isSatisfied(karma: 500, accountAgeDays: 89),
        isFalse,
        reason: 'score met but tenure short',
      );
      expect(
        KarmaGate.moderatorCouncil.isSatisfied(karma: 499, accountAgeDays: 999),
        isFalse,
        reason: 'tenure met but score short',
      );
    });
  });

  group('KarmaGate — strict wire decode', () {
    test('wire round-trip is identity for every gate', () {
      for (final gate in KarmaGate.values) {
        expect(KarmaGate.fromWireName(gate.wireName), gate);
      }
    });

    test('unknown gates throw', () {
      expect(() => KarmaGate.fromWireName('moderator'), throwsArgumentError);
      expect(() => KarmaGate.fromWireName(''), throwsArgumentError);
    });

    test('every gate carries a fixed non-empty label', () {
      for (final gate in KarmaGate.values) {
        expect(gate.label.trim(), isNotEmpty);
      }
    });
  });
}
