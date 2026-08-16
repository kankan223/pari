import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CaseIntakeSubmission (Task 8.1)', () {
    CaseIntakeSubmission base({
      IntakeSituation situation = IntakeSituation.threateningMessages,
      IntakeUrgency urgency = IntakeUrgency.thisWeek,
      bool consent1 = true,
      bool consent2 = true,
    }) =>
        CaseIntakeSubmission(
          situation: situation,
          narrative: 'Someone keeps sending me threats.',
          urgency: urgency,
          consentNotLegalAdvice: consent1,
          consentLegalAidReferral: consent2,
        );

    test('consent gate requires BOTH mandatory consents', () {
      expect(base().consentComplete, isTrue);
      expect(
        base(consent1: false).consentComplete,
        isFalse,
        reason: 'volunteer-analyst consent is mandatory',
      );
      expect(
        base(consent2: false).consentComplete,
        isFalse,
        reason: 'legal-aid referral consent is mandatory',
      );
      expect(
        base(consent1: false, consent2: false).consentComplete,
        isFalse,
      );
    });
    test('provisional severity derives from the situation category', () {
      // No-deadline urgency so the CATEGORY alone drives the severity.
      const noDeadline = IntakeUrgency.noDeadline;
      expect(
        base(
          situation: IntakeSituation.blackmailExtortion,
          urgency: noDeadline,
        ).provisionalSeverity,
        CaseSeverity.high,
      );
      expect(
        base(
          situation: IntakeSituation.intimateImageThreat,
          urgency: noDeadline,
        ).provisionalSeverity,
        CaseSeverity.high,
      );
      expect(
        base(
          situation: IntakeSituation.fakeProfile,
          urgency: noDeadline,
        ).provisionalSeverity,
        CaseSeverity.medium,
      );
      expect(
        base(
          situation: IntakeSituation.tracingHarasser,
          urgency: noDeadline,
        ).provisionalSeverity,
        CaseSeverity.low,
      );
    });

    test('immediate-threat urgency raises the severity floor (never lowers)',
        () {
      // A low-severity category with an immediate threat must be CRITICAL.
      expect(
        base(
          situation: IntakeSituation.tracingHarasser,
          urgency: IntakeUrgency.immediate,
        ).provisionalSeverity,
        CaseSeverity.critical,
      );
      // A high-severity category with NO deadline stays HIGH — urgency never
      // downgrades a serious situation.
      expect(
        base(
          situation: IntakeSituation.blackmailExtortion,
          urgency: IntakeUrgency.noDeadline,
        ).provisionalSeverity,
        CaseSeverity.high,
      );
      // this-week floor raises a low category to MEDIUM.
      expect(
        base(
          situation: IntakeSituation.tracingHarasser,
          urgency: IntakeUrgency.thisWeek,
        ).provisionalSeverity,
        CaseSeverity.medium,
      );
    });

    test('CaseSeverity.maxSeverity is deterministic and order-correct', () {
      expect(CaseSeverity.maxSeverity(CaseSeverity.low, CaseSeverity.critical),
          CaseSeverity.critical);
      expect(CaseSeverity.maxSeverity(CaseSeverity.critical, CaseSeverity.low),
          CaseSeverity.critical);
      expect(CaseSeverity.maxSeverity(CaseSeverity.medium, CaseSeverity.medium),
          CaseSeverity.medium);
      expect(CaseSeverity.maxSeverity(CaseSeverity.high, CaseSeverity.medium),
          CaseSeverity.high);
    });
  });
}
