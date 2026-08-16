import 'package:civic_commons/war_room/domain/analyst.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AnalystSkill.forSituation (Task 8.5 skill-tag mapping)', () {
    test('blackmail maps to threat assessment + OSINT', () {
      final skills =
          AnalystSkill.forSituation(IntakeSituation.blackmailExtortion);
      expect(skills, contains(AnalystSkill.threatAssessment));
      expect(skills, contains(AnalystSkill.osint));
    });

    test('intimate image threat maps to platform takedown + crisis support',
        () {
      final skills =
          AnalystSkill.forSituation(IntakeSituation.intimateImageThreat);
      expect(skills, contains(AnalystSkill.platformTakedown));
      expect(skills, contains(AnalystSkill.crisisSupport));
    });

    test('every situation maps deterministically to non-empty skills', () {
      for (final situation in IntakeSituation.values) {
        final skills = AnalystSkill.forSituation(situation);
        expect(skills, isNotEmpty,
            reason: '$situation must require at least one skill');
        // Repeated calls are identical — deterministic constant map.
        expect(AnalystSkill.forSituation(situation), skills);
      }
    });
  });

  group('AnalystVettingGauntlet (Task 8.5 CTF sandbox)', () {
    const gauntlet = AnalystVettingGauntlet();
    const scenario = 'GAUNTLET-01';

    test('a perfect attempt scores 100 and passes', () {
      const attempt = GauntletAttempt(
        scenarioId: scenario,
        identifiedMarkers: {
          'suspicious_short_url',
          'sender_spoofing',
          'credential_phish',
          'geo_tagged_photo',
        },
      );
      expect(gauntlet.score(attempt), 100);
      expect(gauntlet.passes(attempt), isTrue);
    });

    test('scoring is deterministic — identical attempts score identically', () {
      const attempt = GauntletAttempt(
        scenarioId: scenario,
        identifiedMarkers: {'sender_spoofing', 'credential_phish'},
      );
      final first = gauntlet.score(attempt);
      for (var i = 0; i < 5; i++) {
        expect(gauntlet.score(attempt), first);
      }
    });

    test('an 80% attempt passes (threshold is inclusive)', () {
      const attempt = GauntletAttempt(
        scenarioId: scenario,
        identifiedMarkers: {
          'suspicious_short_url',
          'sender_spoofing',
          'credential_phish',
          // one miss
        },
      );
      expect(gauntlet.score(attempt), 75);
      // 3/4 = 75 < 80 → fails.
      expect(gauntlet.passes(attempt), isFalse);
    });

    test('an empty attempt scores 0 and never passes', () {
      const attempt =
          GauntletAttempt(scenarioId: scenario, identifiedMarkers: {});
      expect(gauntlet.score(attempt), 0);
      expect(gauntlet.passes(attempt), isFalse);
    });

    test('an unknown scenario cannot pass', () {
      const attempt = GauntletAttempt(
        scenarioId: 'GAUNTLET-999',
        identifiedMarkers: {'suspicious_short_url'},
      );
      expect(gauntlet.score(attempt), 0);
      expect(gauntlet.passes(attempt), isFalse);
    });

    test('false-positive markers do not inflate the score', () {
      const attempt = GauntletAttempt(
        scenarioId: scenario,
        identifiedMarkers: {
          'sender_spoofing',
          'credential_phish',
          'irrelevant_marker',
          'another_false_positive',
          'and_another',
        },
      );
      // 2 correct of 4 expected → 50, extra guesses change nothing.
      expect(gauntlet.score(attempt), 50);
    });
  });

  group('Analyst availability (Task 8.5 load + vetting)', () {
    test('a vetted analyst under cap is available for assignment', () {
      const analyst = Analyst(
        analystId: 'AN-0001',
        skills: {AnalystSkill.osint},
        vettingStatus: AnalystVettingStatus.vetted,
        activeCaseCount: 2,
        caseCap: 3,
      );
      expect(analyst.availableForAssignment, isTrue);
    });

    test('an analyst AT cap is never available', () {
      const analyst = Analyst(
        analystId: 'AN-0001',
        skills: {AnalystSkill.osint},
        vettingStatus: AnalystVettingStatus.vetted,
        activeCaseCount: 3,
        caseCap: 3,
      );
      expect(analyst.availableForAssignment, isFalse);
    });

    test('a pending analyst is never available even with capacity', () {
      const analyst = Analyst(
        analystId: 'AN-0007',
        skills: {AnalystSkill.osint},
        vettingStatus: AnalystVettingStatus.pending,
        activeCaseCount: 0,
        caseCap: 3,
      );
      expect(analyst.availableForAssignment, isFalse);
    });

    test('load increments and never decrements below zero', () {
      const analyst = Analyst(
        analystId: 'AN-0001',
        skills: {AnalystSkill.osint},
        vettingStatus: AnalystVettingStatus.vetted,
        activeCaseCount: 1,
      );
      expect(analyst.withIncrementedLoad().activeCaseCount, 2);
      expect(analyst.withDecrementedLoad().activeCaseCount, 0);
      // Decrementing a zero-load analyst stays at zero.
      expect(
        analyst.withDecrementedLoad().withDecrementedLoad().activeCaseCount,
        0,
      );
    });

    test('withVetting promotes to vetted with the earned score', () {
      const analyst = Analyst(
        analystId: 'AN-0007',
        skills: {AnalystSkill.osint},
        vettingStatus: AnalystVettingStatus.pending,
      );
      final vetted = analyst.withVetting(92);
      expect(vetted.vettingStatus, AnalystVettingStatus.vetted);
      expect(vetted.gauntletScore, 92);
    });
  });
}
