import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/state/ui/war_room_case_list_screen.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Full navigation flow (Task 8.1): case list → detail → intake → filed
/// case appears in the list, driven by the real repository + bloc (no
/// fakes), mirroring the composition root wiring.
/// Tall viewport so the consent step's submit button is on-screen.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  WarRoomCase seededCase() => WarRoomCase(
        caseNumber: 'CC-0047',
        title: 'Digital extortion — photo leak threat',
        description: 'd',
        severity: CaseSeverity.high,
        status: CaseStatus.underInvestigation,
        filedAt: t0,
        analystCount: 2,
        estReportHours: 48,
        timeline: const [
          CaseTimelineEntry(label: 'Case filed', done: true),
          CaseTimelineEntry(label: 'Auto-triage complete', done: true),
        ],
      );

  testWidgets('list → detail → intake → filed case round trip with real stores',
      (tester) async {
    _setTallViewport(tester);
    final repo = InMemoryWarCaseRepository(seed: [seededCase()]);
    final bloc = LocalWarRoomBloc(repository: repo);

    Widget shell(Widget child) => MaterialApp(home: child);

    var openedCase = '';
    var filing = false;
    String? filedStamp;

    // --- Case list ---
    await tester.pumpWidget(shell(
      WarRoomCaseListScreen(
        bloc: bloc,
        onCaseTap: (id) => openedCase = id,
        onFileNewCase: () => filing = true,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('▌WAR ROOM▐'), findsOneWidget);
    expect(find.text('CASE #CC-0047'), findsOneWidget);

    // --- List → Detail ---
    await tester.tap(find.text('Digital extortion — photo leak threat'));
    await tester.pump();
    expect(openedCase, 'CC-0047');
    await tester.pumpWidget(shell(
      WarCaseDetailScreen(bloc: bloc, caseNumber: 'CC-0047'),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('STATUS TIMELINE'), findsOneWidget);
    expect(find.text('Case filed'), findsOneWidget);

    // Pause → resume round trip on the open detail.
    await tester.tap(find.text('Pause case'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Resume case'), findsOneWidget);
    await tester.tap(find.text('Resume case'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Pause case'), findsOneWidget);

    // --- Detail → Intake (back to list, then FAB) ---
    await tester.pumpWidget(shell(
      WarRoomCaseListScreen(
        bloc: bloc,
        onCaseTap: (_) {},
        onFileNewCase: () => filing = true,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    await tester.tap(find.byType(FloatingActionButton));
    await tester.pump();
    expect(filing, isTrue);

    await tester.pumpWidget(shell(
      WarRoomIntakeScreen(
        bloc: bloc,
        onFiled: (s) => filedStamp = s,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    expect(find.text('STEP 1 OF 5 — SITUATION OVERVIEW'), findsOneWidget);

    // Complete the intake: extortion → narrative → evidence → urgency →
    // consent → submit.
    await tester.tap(find.text('I am being blackmailed or extorted'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    await tester.enterText(
        find.byType(TextField), 'They have my photos and want money.');
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    await tester.tap(find.text('Continue →')); // evidence (optional)
    await tester.pump();
    await tester
        .tap(find.text('There is an immediate threat or deadline (< 24 hrs)'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    await tester.tap(find.text('Submit case securely'));
    await tester.pump();
    await tester.pump();

    expect(filedStamp, 'CC-0048');

    // --- Back to the list: both cases present, newest first ---
    await tester.pumpWidget(shell(
      WarRoomCaseListScreen(bloc: bloc),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    expect(find.text('CASE #CC-0048'), findsOneWidget);
    expect(find.text('CASE #CC-0047'), findsOneWidget);
    // Immediate-threat extortion → CRITICAL severity band on the new case.
    expect(find.text('CRITICAL SEVERITY'), findsOneWidget);

    await bloc.close();
  });
}
