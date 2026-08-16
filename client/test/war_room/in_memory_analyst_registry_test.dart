import 'package:civic_commons/war_room/data/in_memory_analyst_registry.dart';
import 'package:civic_commons/war_room/domain/analyst.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 16, 10);

  Analyst analyst(String id, Set<AnalystSkill> skills,
          {AnalystVettingStatus status = AnalystVettingStatus.vetted,
          int load = 0,
          int cap = 3}) =>
      Analyst(
        analystId: id,
        skills: skills,
        vettingStatus: status,
        activeCaseCount: load,
        caseCap: cap,
      );

  group('InMemoryAnalystRegistry assignment (Task 8.5)', () {
    test('assigns the least-loaded vetted analyst carrying the skill',
        () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint}, load: 2),
          analyst('AN-0002', {AnalystSkill.osint}, load: 1),
          analyst('AN-0003', {AnalystSkill.osint}, load: 0),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint],
        at: t0,
      );
      expect(assigned, hasLength(1));
      expect(assigned.first.analystId, 'AN-0003',
          reason: 'least-loaded (0) analyst must win');
      expect(assigned.first.caseNumber, 'CC-0001');
      expect(assigned.first.skill, AnalystSkill.osint);
      expect(assigned.first.assignedAt, t0);

      // Load is tracked on the analyst.
      final an3 = await registry.analystById('AN-0003');
      expect(an3!.activeCaseCount, 1);
    });

    test('ties break by blinded handle ascending (deterministic)', () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0002', {AnalystSkill.osint}, load: 1),
          analyst('AN-0001', {AnalystSkill.osint}, load: 1),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint],
        at: t0,
      );
      expect(assigned.single.analystId, 'AN-0001',
          reason: 'equal load → lowest handle wins');
    });

    test('a pending analyst is never assigned', () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint},
              status: AnalystVettingStatus.pending),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint],
        at: t0,
      );
      expect(assigned, isEmpty);
    });

    test('an analyst at cap is skipped', () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint}, load: 3, cap: 3),
          analyst('AN-0002', {AnalystSkill.osint}, load: 0),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint],
        at: t0,
      );
      expect(assigned.single.analystId, 'AN-0002');
    });

    test('assigning multiple skills creates one assignment per skill',
        () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint}),
          analyst('AN-0002', {AnalystSkill.threatAssessment}),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint, AnalystSkill.threatAssessment],
        at: t0,
      );
      expect(assigned, hasLength(2));
      expect(assigned.map((a) => a.skill),
          containsAll([AnalystSkill.osint, AnalystSkill.threatAssessment]));
      // Each skill went to a different analyst — one per skill, blinded.
      final osintId =
          assigned.firstWhere((a) => a.skill == AnalystSkill.osint).analystId;
      final threatId = assigned
          .firstWhere((a) => a.skill == AnalystSkill.threatAssessment)
          .analystId;
      expect(osintId, 'AN-0001');
      expect(threatId, 'AN-0002');
      expect(osintId, isNot(threatId));
    });

    test('a skill with no capacity leaves the gap unfilled (no crash)',
        () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint}, load: 3, cap: 3),
        ],
      );
      final assigned = await registry.assignToCase(
        caseNumber: 'CC-0001',
        skills: [AnalystSkill.osint, AnalystSkill.digitalForensics],
        at: t0,
      );
      // No analyst carries digitalForensics at all → only osint would fill,
      // but it's at cap → nothing assigned.
      expect(assigned, isEmpty);
    });

    test('assignment is deterministic across repeated runs', () async {
      Future<List<CaseAssignment>> run() async {
        final registry = InMemoryAnalystRegistry(
          seed: [
            analyst('AN-0005', {AnalystSkill.osint}, load: 1),
            analyst('AN-0002', {AnalystSkill.osint}, load: 1),
            analyst('AN-0003', {AnalystSkill.osint}, load: 0),
          ],
        );
        return registry.assignToCase(
          caseNumber: 'CC-0001',
          skills: [AnalystSkill.osint],
          at: t0,
        );
      }

      final first = await run();
      for (var i = 0; i < 3; i++) {
        final again = await run();
        expect(again.single.analystId, first.single.analystId);
      }
    });
  });

  group('InMemoryAnalystRegistry load + vetting (Task 8.5)', () {
    test('releaseFromCase decrements the analyst load', () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0001', {AnalystSkill.osint}, load: 1)
        ],
      );
      await registry.releaseFromCase(
          caseNumber: 'CC-0001', analystId: 'AN-0001');
      final an1 = await registry.analystById('AN-0001');
      expect(an1!.activeCaseCount, 0);
    });

    test('runGauntlet promotes a pending analyst on a passing attempt',
        () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0007', {AnalystSkill.osint},
              status: AnalystVettingStatus.pending),
        ],
      );
      final updated = await registry.runGauntlet(
        analystId: 'AN-0007',
        attempt: const GauntletAttempt(
          scenarioId: 'GAUNTLET-01',
          identifiedMarkers: {
            'suspicious_short_url',
            'sender_spoofing',
            'credential_phish',
            'geo_tagged_photo',
          },
        ),
      );
      expect(updated.vettingStatus, AnalystVettingStatus.vetted);
      expect(updated.gauntletScore, 100);
      // The registry persisted the promotion.
      expect((await registry.analystById('AN-0007'))!.vettingStatus,
          AnalystVettingStatus.vetted);
    });

    test('a failing gauntlet attempt leaves the analyst pending', () async {
      final registry = InMemoryAnalystRegistry(
        seed: [
          analyst('AN-0007', {AnalystSkill.osint},
              status: AnalystVettingStatus.pending),
        ],
      );
      final updated = await registry.runGauntlet(
        analystId: 'AN-0007',
        attempt: const GauntletAttempt(
          scenarioId: 'GAUNTLET-01',
          identifiedMarkers: {'geo_tagged_photo'},
        ),
      );
      expect(updated.vettingStatus, AnalystVettingStatus.pending);
    });

    test('runGauntlet on an unknown analyst throws StateError', () async {
      final registry = InMemoryAnalystRegistry();
      expect(
        () => registry.runGauntlet(
          analystId: 'AN-9999',
          attempt: const GauntletAttempt(
              scenarioId: 'GAUNTLET-01', identifiedMarkers: {}),
        ),
        throwsStateError,
      );
    });

    test('the production pool is six vetted analysts with distinct skills',
        () async {
      final registry = InMemoryAnalystRegistry.production();
      final analysts = await registry.listAnalysts();
      expect(analysts, hasLength(6));
      for (final a in analysts) {
        expect(a.vettingStatus, AnalystVettingStatus.vetted);
        expect(a.skills, isNotEmpty);
        expect(a.analystId, matches(r'^AN-\d{4}$'));
        expect(a.analystId.contains('@'), isFalse,
            reason: 'handles must never look like identity');
      }
    });
  });
}
