import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/severity_scoring.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const scorer = SeverityScorer();

  SeverityTriage score({
    required String narrative,
    CaseSeverity floor = CaseSeverity.low,
    IntakeUrgency urgency = IntakeUrgency.noDeadline,
  }) =>
      scorer.score(
          narrative: narrative, floorSeverity: floor, urgency: urgency);

  group('SeverityScorer (Task 8.4)', () {
    test('CRITICAL keywords score critical', () {
      final r = score(narrative: 'my photos were leaked and went viral');
      expect(r.severity, CaseSeverity.critical);
      expect(r.criticalSignals, greaterThanOrEqualTo(1));
    });

    test('2+ HIGH keywords score high', () {
      final r = score(narrative: 'he threatened me and demanded money to stop');
      expect(r.severity, CaseSeverity.high);
      expect(r.highSignals, greaterThanOrEqualTo(2));
    });

    test('1 HIGH keyword scores medium', () {
      final r = score(narrative: 'he demanded money for silence');
      expect(r.severity, CaseSeverity.medium);
      expect(r.highSignals, 1);
    });

    test('1 HIGH + urgency signal scores high', () {
      final r =
          score(narrative: 'he threatened me and wants payment immediately');
      expect(r.severity, CaseSeverity.high);
      expect(r.urgencySignals, greaterThanOrEqualTo(1));
    });

    test('2+ MEDIUM keywords score medium', () {
      final r = score(narrative: 'a fake profile is impersonating me');
      expect(r.severity, CaseSeverity.medium);
      expect(r.mediumSignals, greaterThanOrEqualTo(2));
    });

    test('no keywords scores low', () {
      final r = score(narrative: 'nothing unusual happened yesterday');
      expect(r.severity, CaseSeverity.low);
      expect(r.signalLabels, isEmpty);
    });

    test('situation floor never downgrades a serious category', () {
      // Blackmail category (high floor) with a neutral narrative → HIGH.
      final r = score(
        narrative: 'they contacted me yesterday',
        floor: CaseSeverity.high,
      );
      expect(r.severity, CaseSeverity.high,
          reason: 'a serious category can never be scored below its band');
    });

    test('urgency floor holds — immediate urgency scores at least medium', () {
      final r = score(
        narrative: 'just some questions',
        urgency: IntakeUrgency.thisWeek, // floor = medium
      );
      expect(r.severity, CaseSeverity.medium);
    });

    test('immediate urgency + threat scores critical (max merge)', () {
      final r = score(
        narrative: 'threatened with an immediate deadline tonight',
        urgency: IntakeUrgency.immediate, // floor = critical
      );
      expect(r.severity, CaseSeverity.critical);
    });

    test('SLA mapping is deterministic per severity', () {
      expect(SeverityScorer.slaHoursFor(CaseSeverity.critical), 24);
      expect(SeverityScorer.slaHoursFor(CaseSeverity.high), 48);
      expect(SeverityScorer.slaHoursFor(CaseSeverity.medium), 72);
      expect(SeverityScorer.slaHoursFor(CaseSeverity.low), 120);
      expect(score(narrative: 'leaked').slaHours, 24);
    });

    test(
        'DETERMINISM: identical input → identical output (SECURITY CHECKPOINT)',
        () {
      const narrative = 'he leaked my photos and is threatening me for money';
      final a = score(narrative: narrative);
      final b = score(narrative: narrative);
      final c = score(narrative: narrative);
      expect(a.severity, b.severity);
      expect(a.severity, c.severity);
      expect(a.signalLabels, b.signalLabels);
      expect(a.criticalSignals, b.criticalSignals);
      expect(a.highSignals, b.highSignals);
    });

    test('signal labels are fixed, non-PII labels — never matched text', () {
      final r = score(narrative: 'leaked and threatening with money');
      for (final label in r.signalLabels) {
        expect(label, isNot(contains('leaked')));
        expect(label, isNot(contains('threatening')));
        expect(label, isNot(contains('money')));
        expect(label, matches(RegExp(r'^\d+× .+ signal$')));
      }
    });
  });
}
