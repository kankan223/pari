import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/encrypted_intake_draft_store.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Task 8.7 integration: a REAL pause → exit → resume → complete round trip
/// with the REAL encrypted draft store + repository + bloc (no fakes except
/// the in-memory entity store backing the sealed drafts). The paused draft
/// survives the navigation away, restores the exact step, and the case is
/// filed with the resumed content.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
      'pause → exit → reopen → resume → complete: zero data loss, sealed at '
      'rest', (tester) async {
    _setTallViewport(tester);
    final repo = InMemoryWarCaseRepository();
    final draftStore = EncryptedIntakeDraftStore(
      store: InMemoryEntityStore<IntakeDraftRecord>((r) => r.id),
      cipher: testCipher(),
    );
    final bloc = LocalWarRoomBloc(repository: repo);
    var paused = false;
    String? filedStamp;

    Future<void> pumpIntake() async {
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          draftStore: draftStore,
          onPaused: () => paused = true,
          onFiled: (s) => filedStamp = s,
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    // --- Session 1: fill steps 1-3, then Pause & Save (exit). ---
    await pumpIntake();
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
    // Step 4 — urgency selected so the resumed draft can file cleanly.
    await tester.tap(find.text('This needs attention soon (this week)'));
    await tester.pump();

    await tester.tap(find.text('Pause & Save'));
    await tester.pump();
    await tester.pump();
    expect(paused, isTrue, reason: 'pausing exits the flow');
    expect(await draftStore.listDrafts(), hasLength(1),
        reason: 'the draft is sealed at rest immediately');

    // --- Session 2: reopen (fresh state — unmount first so initState
    // reloads the sealed draft) — resume banner → Resume → complete. ---
    await tester.pumpWidget(const SizedBox());
    await pumpIntake();
    expect(find.text('You have a saved draft'), findsOneWidget);
    await tester.tap(find.text('Resume draft'));
    await tester.pump();
    await tester.pump();

    // Restored to step 4 (urgency) with the situation + narrative back.
    expect(find.text('STEP 4 OF 5 — URGENCY'), findsOneWidget);
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    await tester.tap(find.text('Submit case securely'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(filedStamp, 'CC-0001');
    final filed = await repo.getCaseById('CC-0001');
    expect(filed, isNotNull);
    expect(filed!.description, 'They have my photos and want money.',
        reason: 'the resumed narrative is filed intact — zero data loss');

    await bloc.close();
  });
}
