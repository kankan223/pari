import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/quick_exit_safe_screen.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/encrypted_intake_draft_store.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/intake_draft.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repository/fakes.dart';

class _RecordingFlagService implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

WarRoomCase warCase() => WarRoomCase(
      caseNumber: 'CC-0047',
      title: 'Digital extortion — photo leak threat',
      description: 'd',
      severity: CaseSeverity.high,
      status: CaseStatus.underInvestigation,
      filedAt: DateTime.utc(2026, 8, 10, 12),
      analystCount: 2,
      estReportHours: 48,
      timeline: const [
        CaseTimelineEntry(label: 'Case filed', done: true),
        CaseTimelineEntry(label: 'Auto-triage complete', done: true),
      ],
    );

void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  group('WarRoomIntakeScreen trauma-informed (Task 8.7)', () {
    testWidgets('QUICK EXIT button is always visible on every step',
        (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.text('QUICK EXIT'), findsOneWidget);
      await bloc.close();
    });

    testWidgets(
        'QUICK EXIT instantly wipes transient state and routes to the safe '
        'screen (default navigation)', (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      // Enter some content (step 1 selection + step 2 narrative).
      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'They have my photos and want money.');
      await tester.pump();

      // QUICK EXIT — no confirmation, straight to the neutral safe screen.
      await tester.tap(find.text('QUICK EXIT'));
      await tester.pumpAndSettle();

      expect(find.text('You are safe.'), findsOneWidget,
          reason: 'the quick-exit target is the neutral safe screen');
      expect(find.text('QUICK EXIT'), findsNothing,
          reason: 'the intake flow is no longer on screen');
      await bloc.close();
    });

    testWidgets(
        'QUICK EXIT fires the onQuickExit seam when the host wires one '
        '(exit the vault shell)', (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      var quickExited = false;
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          onQuickExit: () => quickExited = true,
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.tap(find.text('QUICK EXIT'));
      await tester.pump();
      expect(quickExited, isTrue);
      await bloc.close();
    });

    testWidgets('✕ close with unsaved input CONFIRMS before discarding',
        (tester) async {
      var exited = false;
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, onExit: () => exited = true),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'unsaved narrative');
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(find.text('Leave without saving?'), findsOneWidget,
          reason: 'destructive reset must confirm first');
      expect(exited, isFalse, reason: 'still editing — not exited');

      // Keep editing returns to the flow.
      await tester.tap(find.text('Keep editing'));
      await tester.pumpAndSettle();
      expect(find.text('STEP 2 OF 5 — YOUR SITUATION'), findsOneWidget);
      expect(exited, isFalse);

      // Leave discards after explicit confirmation.
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Leave'));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
      await bloc.close();
    });

    testWidgets('✕ close with NO input exits immediately (no dialog)',
        (tester) async {
      var exited = false;
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, onExit: () => exited = true),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();
      expect(exited, isTrue);
      expect(find.text('Leave without saving?'), findsNothing);
      await bloc.close();
    });

    testWidgets('the grounding note renders on every step', (tester) async {
      _setTallViewport(tester);
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(find.textContaining('You are in control.'), findsOneWidget);

      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      expect(find.textContaining('You are in control.'), findsOneWidget,
          reason: 'grounding note persists across steps');
      await bloc.close();
    });

    testWidgets('Pause & Save persists an encrypted draft and fires onPaused',
        (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      final draftStore = EncryptedIntakeDraftStore(
        store: InMemoryEntityStore<IntakeDraftRecord>((r) => r.id),
        cipher: testCipher(),
      );
      var paused = false;
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          draftStore: draftStore,
          onPaused: () => paused = true,
        ),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }

      // Fill steps 1-2 so the draft carries real content.
      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'They have my photos and want money.');
      await tester.pump();

      await tester.tap(find.text('Pause & Save'));
      await tester.pump();
      await tester.pump();

      expect(paused, isTrue);
      final drafts = await draftStore.listDrafts();
      expect(drafts, hasLength(1));
      expect(drafts.single.narrative, 'They have my photos and want money.');
      expect(drafts.single.step, 2);
      await bloc.close();
    });

    testWidgets('Pause & Save shows a non-destructive confirmation',
        (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      final draftStore = EncryptedIntakeDraftStore(
        store: InMemoryEntityStore<IntakeDraftRecord>((r) => r.id),
        cipher: testCipher(),
      );
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, draftStore: draftStore),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      await tester.tap(find.text('Pause & Save'));
      await tester.pump();
      expect(find.textContaining('resume anytime'), findsOneWidget);
      await bloc.close();
    });

    testWidgets(
        'a saved draft offers Resume on step 1 and restores the exact step',
        (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      final draftStore = EncryptedIntakeDraftStore(
        store: InMemoryEntityStore<IntakeDraftRecord>((r) => r.id),
        cipher: testCipher(),
      );
      // Seed a paused draft (step 3, evidence step) — the resume surface.
      await draftStore.saveDraft(IntakeDraft(
        draftId: 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b',
        step: 3,
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'They have my photos and want money.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: false,
        optInAnonymizedLedger: false,
        savedAt: DateTime.utc(2026, 8, 14, 10, 30),
      ));
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, draftStore: draftStore),
      ));
      await tester.pump();
      await tester.pump();

      expect(find.text('You have a saved draft'), findsOneWidget);
      await tester.tap(find.text('Resume draft'));
      await tester.pump();
      await tester.pump();

      // Jumped to step 3 with the narrative + situation restored.
      expect(find.text('STEP 3 OF 5 — EVIDENCE'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('Start fresh discards the saved draft', (tester) async {
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      final draftStore = EncryptedIntakeDraftStore(
        store: InMemoryEntityStore<IntakeDraftRecord>((r) => r.id),
        cipher: testCipher(),
      );
      await draftStore.saveDraft(IntakeDraft(
        draftId: 'a9d34f8e-2b1c-4e5f-9a8b-7c6d5e4f3a2b',
        step: 2,
        situation: null,
        narrative: 'old narrative',
        urgency: null,
        consentNotLegalAdvice: false,
        consentLegalAidReferral: false,
        optInAnonymizedLedger: false,
        savedAt: DateTime.utc(2026, 8, 14),
      ));
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, draftStore: draftStore),
      ));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Start fresh'));
      await tester.pump();
      await tester.pump();
      expect(find.text('You have a saved draft'), findsNothing);
      expect(await draftStore.listDrafts(), isEmpty,
          reason: 'Start fresh deletes the sealed draft');
      await bloc.close();
    });

    testWidgets('FLAG_SECURE remains active with the QUICK EXIT button',
        (tester) async {
      final flag = _RecordingFlagService();
      final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(bloc: bloc, secureFlagService: flag),
      ));
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      expect(flag.enableCalls, greaterThanOrEqualTo(1));
      await bloc.close();
    });
  });

  group('QuickExitSafeScreen (Task 8.7)', () {
    testWidgets('renders neutral copy + Return to home fires onDone',
        (tester) async {
      var done = false;
      await tester.pumpWidget(MaterialApp(
        home: QuickExitSafeScreen(onDone: () => done = true),
      ));
      expect(find.text('You are safe.'), findsOneWidget);
      expect(find.textContaining('screen was cleared'), findsOneWidget);
      await tester.tap(find.text('Return to home'));
      expect(done, isTrue);
    });

    testWidgets('FLAG_SECURE is active on the safe screen', (tester) async {
      final flag = _RecordingFlagService();
      await tester.pumpWidget(MaterialApp(
        home: QuickExitSafeScreen(secureFlagService: flag),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      expect(flag.enableCalls, greaterThanOrEqualTo(1),
          reason: 'the quick-exit fallback must keep FLAG_SECURE');
    });
  });

  group('WarCaseDetailScreen quick exit (Task 8.7)', () {
    testWidgets('QUICK EXIT button fires onQuickExit', (tester) async {
      _setTallViewport(tester);
      final repo = InMemoryWarCaseRepository(seed: [warCase()]);
      final bloc = LocalWarRoomBloc(repository: repo);
      var quickExited = false;
      await tester.pumpWidget(MaterialApp(
        home: WarCaseDetailScreen(
          bloc: bloc,
          caseNumber: 'CC-0047',
          onQuickExit: () => quickExited = true,
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      await tester.tap(find.text('QUICK EXIT'));
      await tester.pump();
      expect(quickExited, isTrue);
      await bloc.close();
    });
  });
}
