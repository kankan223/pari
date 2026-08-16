import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_analyst_registry.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/analyst.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 8.5 end-to-end with REAL stores (no fakes): file a case → the
/// deterministic registry auto-assigns a skill-matched blinded team → the
/// detail renders the ANALYST TEAM section → a blinded analyst note lands on
/// the case → an unassigned analyst cannot post → withdraw releases load.
void main() {
  const submission = CaseIntakeSubmission(
    situation: IntakeSituation.blackmailExtortion,
    narrative: 'They are blackmailing me with leaked photos.',
    urgency: IntakeUrgency.thisWeek,
    consentNotLegalAdvice: true,
    consentLegalAidReferral: true,
  );

  testWidgets('file → auto-assign → team + blinded note (real stores)',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final registry = InMemoryAnalystRegistry.production();
    final repo = InMemoryWarCaseRepository(registry: registry);
    final bloc = LocalWarRoomBloc(repository: repo);
    await bloc.start();

    // File the case through the REAL repository → deterministic assignment.
    final filed = await repo.fileCase(submission);
    expect(filed.assignments, isNotEmpty);
    expect(filed.analystCount, filed.assignments.length);
    final requiredSkills =
        AnalystSkill.forSituation(IntakeSituation.blackmailExtortion);
    for (final a in filed.assignments) {
      expect(requiredSkills, contains(a.skill));
    }

    // Open the detail — the ANALYST TEAM section renders blinded handles.
    await bloc.openCase(filed.caseNumber);
    await tester.pumpWidget(MaterialApp(
      home: WarCaseDetailScreen(
        bloc: bloc,
        caseNumber: filed.caseNumber,
      ),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.text('ANALYST TEAM'), findsOneWidget);
    for (final a in filed.assignments) {
      expect(find.text(a.analystId), findsOneWidget);
    }

    // A blinded analyst note flows through the REAL bloc to the UI.
    final analystId = filed.assignments.first.analystId;
    await bloc.addAnalystUpdate(
        filed.caseNumber, analystId, 'Origin platform identified.', 'Done');
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    expect(find.textContaining('Origin platform'), findsOneWidget);
    expect(find.textContaining(analystId), findsWidgets);

    // Blind-review enforcement: an analyst NOT on the case cannot post.
    await expectLater(
      bloc.addAnalystUpdate(
          filed.caseNumber, 'AN-0099', 'stranger note', 'In progress'),
      throwsStateError,
    );

    // Withdraw releases the team's load.
    await repo.withdraw(filed.caseNumber);
    for (final a in filed.assignments) {
      expect((await registry.analystById(a.analystId))!.activeCaseCount, 0);
    }
    await bloc.close();
  });

  test('a second case never double-assigns an at-cap analyst', () async {
    final registry = InMemoryAnalystRegistry(seed: [
      const Analyst(
        analystId: 'AN-0001',
        skills: {AnalystSkill.osint, AnalystSkill.threatAssessment},
        vettingStatus: AnalystVettingStatus.vetted,
        caseCap: 1,
      ),
    ]);
    final repo = InMemoryWarCaseRepository(registry: registry);

    final first = await repo.fileCase(submission);
    expect(first.assignments, hasLength(2),
        reason: 'one analyst with both skills takes both skill slots');
    // Load counts CASES, not skill-slots: one case = load 1 (at cap).
    expect((await registry.analystById('AN-0001'))!.activeCaseCount, 1);

    final second = await repo.fileCase(submission);
    expect(second.assignments, isEmpty,
        reason: 'an at-cap analyst must never take a second case');
  });
}
