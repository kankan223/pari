import 'package:civic_commons/war_room/data/in_memory_analyst_registry.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/analyst.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:civic_commons/war_room/domain/severity_scoring.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);
  WarRoomCase makeCase(String stamp,
          {CaseSeverity severity = CaseSeverity.high,
          CaseStatus status = CaseStatus.underInvestigation,
          DateTime? filedAt}) =>
      WarRoomCase(
        caseNumber: stamp,
        title: 'Digital extortion — photo leak threat',
        description: 'd',
        severity: severity,
        status: status,
        filedAt: filedAt ?? t0,
        analystCount: 2,
        estReportHours: 48,
      );

  CaseIntakeSubmission submission(
          {IntakeSituation situation = IntakeSituation.blackmailExtortion,
          IntakeUrgency urgency = IntakeUrgency.thisWeek}) =>
      CaseIntakeSubmission(
        situation: situation,
        narrative: 'They say they will leak my photos.',
        urgency: urgency,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      );

  group('InMemoryWarCaseRepository (Task 8.1)', () {
    test('listCases returns newest-filed first', () async {
      final repo = InMemoryWarCaseRepository(seed: [
        makeCase('CC-0001',
            status: CaseStatus.reportReady,
            filedAt: t0.subtract(const Duration(days: 2))),
        makeCase('CC-0002', filedAt: t0),
      ]);
      final cases = await repo.listCases();
      expect(cases.map((c) => c.caseNumber), ['CC-0002', 'CC-0001']);
    });

    test('getCaseById returns the case or null', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      expect((await repo.getCaseById('CC-0001'))!.caseNumber, 'CC-0001');
      expect(await repo.getCaseById('CC-9999'), isNull);
    });

    test('fileCase assigns sequential dossier stamps and a timeline', () async {
      final repo = InMemoryWarCaseRepository(nextNumber: 47);
      final filed = await repo.fileCase(submission());
      expect(filed.caseNumber, 'CC-0047');
      // Task 8.5: skill-matched auto-assignment moves the case to
      // investigationOngoing with a blinded team on board.
      expect(filed.status, CaseStatus.investigationOngoing);
      expect(filed.analystCount, greaterThan(0));
      expect(filed.assignments, isNotEmpty);
      // Task 8.4: the deterministic keyword engine scores the narrative
      // ('leak my photos' → HIGH signals) and the SLA follows the score.
      expect(filed.severity, CaseSeverity.high);
      expect(filed.triage, isNotNull);
      expect(filed.triage!.severity, CaseSeverity.high);
      expect(filed.estReportHours, 48);
      expect(filed.timeline, hasLength(6));
      expect(filed.timeline.first.label, 'Case filed');
      expect(filed.timeline.first.done, isTrue);
      expect(filed.timeline[1].detail, contains('SLA'));
      // The 'Analysts assigned' checkpoint is done with the blinded team.
      expect(filed.timeline[2].label, 'Analysts assigned');
      expect(filed.timeline[2].done, isTrue);
      expect(filed.timeline[2].detail, contains('skill-matched'));
      expect(filed.timeline.last.label, 'Choose next step');

      final second = await repo.fileCase(submission());
      expect(second.caseNumber, 'CC-0048');
      expect(await repo.getCaseById('CC-0047'), isNotNull);
      expect(await repo.getCaseById('CC-0048'), isNotNull);
    });

    test('stamp sequence continues above any seeded maximum', () async {
      final repo = InMemoryWarCaseRepository(
        seed: [makeCase('CC-0099')],
        nextNumber: 1,
      );
      final filed = await repo.fileCase(submission());
      expect(filed.caseNumber, 'CC-0100',
          reason: 'seeded stamp 99 must not be reissued');
    });

    test('setPaused toggles the paused flag without changing lifecycle',
        () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final paused = await repo.setPaused('CC-0001', true);
      expect(paused.paused, isTrue);
      expect(paused.status, CaseStatus.underInvestigation);
      final resumed = await repo.setPaused('CC-0001', false);
      expect(resumed.paused, isFalse);
    });

    test('withdraw moves the case to withdrawn', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final withdrawn = await repo.withdraw('CC-0001');
      expect(withdrawn.status, CaseStatus.withdrawn);
    });

    test('unknown case operations throw StateError (no silent corrupt state)',
        () async {
      final repo = InMemoryWarCaseRepository();
      expect(() => repo.setPaused('CC-0001', true), throwsStateError);
      expect(() => repo.withdraw('CC-0001'), throwsStateError);
      expect(
        () => repo.overrideSeverity(
            'CC-0001',
            SeverityOverride(
                newSeverity: CaseSeverity.low, reason: 'r', at: t0)),
        throwsStateError,
      );
    });
  });

  group('InMemoryWarCaseRepository triage & override (Task 8.4)', () {
    test('overrideSeverity re-bands the case and updates the SLA projection',
        () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final override = SeverityOverride(
        newSeverity: CaseSeverity.critical,
        reason: 'Victim reports the leak is already public',
        at: t0.add(const Duration(hours: 1)),
      );
      final updated = await repo.overrideSeverity('CC-0001', override);
      expect(updated.severity, CaseSeverity.critical);
      expect(updated.severityOverride, isNotNull);
      expect(updated.severityOverride!.newSeverity, CaseSeverity.critical);
      expect(updated.severityOverride!.reason, contains('public'));
      expect(updated.estReportHours, 24,
          reason: 'the SLA projection follows the overridden band');
      // The original triage stays for the audit trail.
      expect(updated.triage, isNull); // seeded case has no triage

      final read = await repo.getCaseById('CC-0001');
      expect(read!.severity, CaseSeverity.critical);
      expect(read.severityOverride!.at, t0.add(const Duration(hours: 1)));
    });

    test('override requires a non-empty reason', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      await expectLater(
        repo.overrideSeverity(
          'CC-0001',
          SeverityOverride(
            newSeverity: CaseSeverity.medium,
            reason: '   ',
            at: t0,
          ),
        ),
        throwsArgumentError,
      );
      expect((await repo.getCaseById('CC-0001'))!.severity, CaseSeverity.high,
          reason: 'a rejected override must not change the case');
    });

    test('the scorer is injectable (deterministic stub for tests)', () async {
      final repo = InMemoryWarCaseRepository(
        scorer: _FixedScorer(CaseSeverity.medium),
      );
      final filed = await repo.fileCase(submission());
      expect(filed.severity, CaseSeverity.medium);
      expect(filed.estReportHours, 72);
    });
  });

  group('Analyst assignment & blind review (Task 8.5)', () {
    test('fileCase auto-assigns a skill-matched blinded team', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      expect(filed.analystCount, greaterThan(0));
      expect(filed.assignments, isNotEmpty);
      // Every assignment is skill-matched to the situation's required skills.
      final required =
          AnalystSkill.forSituation(IntakeSituation.blackmailExtortion);
      for (final a in filed.assignments) {
        expect(required, contains(a.skill));
        expect(a.analystId, matches(r'^AN-\d{4}$'),
            reason: 'handles are blinded AN-#### stamps, never identity');
        expect(a.caseNumber, filed.caseNumber);
      }
      // Distinct skills → distinct analysts (one per skill).
      expect(filed.assignments.map((a) => a.analystId).toSet().length,
          filed.assignments.length);
    });

    test('withdraw releases the assigned analysts\' load', () async {
      final registry = InMemoryAnalystRegistry(seed: [
        _analyst('AN-0001', {AnalystSkill.osint}),
        _analyst('AN-0002', {AnalystSkill.threatAssessment}),
      ]);
      final repo = InMemoryWarCaseRepository(registry: registry);
      final filed = await repo.fileCase(submission());
      expect(filed.analystCount, 2);
      for (final a in filed.assignments) {
        expect((await registry.analystById(a.analystId))!.activeCaseCount, 1);
      }

      await repo.withdraw(filed.caseNumber);
      for (final a in filed.assignments) {
        expect((await registry.analystById(a.analystId))!.activeCaseCount, 0,
            reason: 'withdraw must release analyst load');
      }
    });

    test('an analyst with the required skill is assigned the right case',
        () async {
      // Only AN-0002 carries threat assessment; only AN-0001 carries OSINT.
      final registry = InMemoryAnalystRegistry(seed: [
        _analyst('AN-0001', {AnalystSkill.osint}),
        _analyst('AN-0002', {AnalystSkill.threatAssessment}),
      ]);
      final repo = InMemoryWarCaseRepository(registry: registry);
      final filed = await repo.fileCase(submission());
      final skills = filed.assignments.map((a) => a.skill).toSet();
      expect(skills,
          containsAll([AnalystSkill.osint, AnalystSkill.threatAssessment]));
      final osintId = filed.assignments
          .firstWhere((a) => a.skill == AnalystSkill.osint)
          .analystId;
      expect(osintId, 'AN-0001');
    });

    test(
        'addAnalystUpdate posts a note attributed ONLY via the blinded '
        'handle', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final analystId = filed.assignments.first.analystId;

      final updated = await repo.addAnalystUpdate(
        filed.caseNumber,
        analystId,
        'Traced the account to a compromised sim.',
        'In progress',
      );
      expect(updated.updates, hasLength(1));
      expect(updated.updates.single.analystId, analystId);
      expect(updated.updates.single.text, contains('Traced'));
      expect(updated.updates.single.progress, 'In progress');
    });

    test('an analyst NOT assigned to the case cannot post (blind review)',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      await expectLater(
        repo.addAnalystUpdate(
            filed.caseNumber, 'AN-0099', 'Should not post', 'In progress'),
        throwsStateError,
        reason: 'a stranger analyst must never be able to write on a case',
      );
    });

    test('updates never carry another analyst\'s identity (blinded notes)',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final first = filed.assignments.first.analystId;
      await repo.addAnalystUpdate(
          filed.caseNumber, first, 'First note', 'In progress');
      final read = await repo.getCaseById(filed.caseNumber);
      // The only attribution on every note is a blinded handle.
      for (final u in read!.updates) {
        expect(u.analystId, matches(r'^AN-\d{4}$'));
        expect(u.text.contains('AN-'), isFalse,
            reason: 'note text must never reference another analyst');
      }
    });
  });

  group('InMemoryWarCaseRepository · Task 8.6 custody', () {
    test('fileCase records the filed → triage → assigned custody chain',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());

      final events = await repo.custodyEvents(filed.caseNumber);
      expect(events, isNotEmpty);
      expect(events.first.type, CustodyEventType.caseFiled);
      expect(events.first.actor, 'VICTIM');
      expect(
          events.map((e) => e.type),
          containsAll(
              [CustodyEventType.autoTriage, CustodyEventType.analystAssigned]));
      // Chain links: every event (after the first) references the prior.
      for (var i = 1; i < events.length; i++) {
        expect(events[i].prevHash, events[i - 1].selfHash);
      }
      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('withdraw appends a CASE WITHDRAWN event (append-only grows)',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final before = (await repo.custodyEvents(filed.caseNumber)).length;

      await repo.withdraw(filed.caseNumber);
      final events = await repo.custodyEvents(filed.caseNumber);
      expect(events, hasLength(before + 1));
      expect(events.last.type, CustodyEventType.caseWithdrawn);
      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('overrideSeverity + addAnalystUpdate append their custody events',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());

      await repo.overrideSeverity(
        filed.caseNumber,
        SeverityOverride(
          newSeverity: CaseSeverity.critical,
          reason: 'Repeated blackmail demands in 24h',
          at: t0,
        ),
      );
      final analystId = filed.assignments.first.analystId;
      await repo.addAnalystUpdate(
          filed.caseNumber, analystId, 'Traced the account', 'In progress');

      final types = (await repo.custodyEvents(filed.caseNumber))
          .map((e) => e.type)
          .toList();
      expect(types, contains(CustodyEventType.severityOverride));
      expect(types, contains(CustodyEventType.analystUpdate));
      // The update event is attributed via the blinded handle.
      final updateEvent = (await repo.custodyEvents(filed.caseNumber))
          .firstWhere((e) => e.type == CustodyEventType.analystUpdate);
      expect(updateEvent.actor, analystId);
      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('custody events carry ZERO identity — fixed labels + blinded actors',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final analystId = filed.assignments.first.analystId;
      await repo.addAnalystUpdate(
          filed.caseNumber, analystId, 'A note', 'In progress');

      final events = await repo.custodyEvents(filed.caseNumber);
      final json = events.map((e) => e.toJson().toString()).join(' ');
      for (final forbidden in [
        'phone',
        'email',
        '+91',
        '@',
        filed.description,
      ]) {
        expect(json.toLowerCase(), isNot(contains(forbidden.toLowerCase())),
            reason: 'custody events must never leak $forbidden');
      }
      // The only actors are VICTIM / SYSTEM / AN-####.
      for (final e in events) {
        expect(e.actor, matches(r'^(VICTIM|SYSTEM|AN-\d{4})$'));
      }
    });

    test('signVerifiedReport returns a verifiable HMAC + custody event',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());

      final signed = await repo.signVerifiedReport(filed.caseNumber);
      expect(signed.signature, isNotEmpty);
      expect(signed.report.caseNumber, filed.caseNumber);
      expect(signed.report.severityLabel, filed.severity.label);
      expect(signed.report.analystCount, filed.analystCount);
      // The report is deterministic — re-signing yields the same signature.
      final again = await repo.signVerifiedReport(filed.caseNumber);
      expect(again.signature, signed.signature,
          reason: 'the HMAC must be deterministic for the same report');

      final types = (await repo.custodyEvents(filed.caseNumber))
          .map((e) => e.type)
          .toList();
      expect(types, contains(CustodyEventType.reportSigned));
      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('queueLegalAidHandoff returns an id + handoff custody event',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());

      final id = await repo.queueLegalAidHandoff(filed.caseNumber);
      expect(id, isNotEmpty);
      final types = (await repo.custodyEvents(filed.caseNumber))
          .map((e) => e.type)
          .toList();
      expect(types, contains(CustodyEventType.handoffQueued));
      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });
  });
}

Analyst _analyst(String id, Set<AnalystSkill> skills) => Analyst(
      analystId: id,
      skills: skills,
      vettingStatus: AnalystVettingStatus.vetted,
    );

/// A fixed-outcome scorer — proves the repository honors the injected seam
/// and that the engine itself is what varies (not the repository).
class _FixedScorer extends SeverityScorer {
  final CaseSeverity outcome;
  _FixedScorer(this.outcome);

  @override
  SeverityTriage score({
    required String narrative,
    required CaseSeverity floorSeverity,
    required IntakeUrgency urgency,
  }) =>
      SeverityTriage(
        severity: outcome,
        criticalSignals: 0,
        highSignals: 0,
        mediumSignals: 0,
        urgencySignals: 0,
        slaHours: SeverityScorer.slaHoursFor(outcome),
      );
}
