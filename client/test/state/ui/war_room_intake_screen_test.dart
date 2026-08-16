import 'dart:typed_data';

import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/evidence_item.dart';
import 'package:civic_commons/war_room/domain/evidence_ports.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

class _FakePicker implements EvidencePicker {
  final List<PickedEvidence> queue;
  int calls = 0;

  _FakePicker([this.queue = const []]);

  @override
  Future<PickedEvidence?> pick() async {
    calls++;
    if (queue.isEmpty) {
      return null;
    }
    return queue.removeAt(0);
  }
}

/// Fake evidence sink that records locally without real crypto.
class _FakeEvidenceSink implements EvidenceSink {
  final List<EvidenceRecord> rows = [];

  @override
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence) async {
    final id = 'ev-${rows.length + 1}';
    rows.add(EvidenceRecord(
      id: id,
      caseNumber: caseNumber,
      sealedFile: Uint8List.fromList([9, 9, 9]),
      dekEnvelope: Uint8List.fromList([8, 8, 8]),
      sizeBytes: evidence.sizeBytes,
      mimeType: evidence.mimeType,
      createdAt: DateTime.utc(2026, 8, 12),
    ));
    return id;
  }

  @override
  Future<List<EvidenceRecord>> localEvidence() async => List.of(rows);

  @override
  Future<void> removeEvidence(String evidenceId) async {}
}

/// Tall viewport so the consent step's submit button is on-screen.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  Future<LocalWarRoomBloc> pump(WidgetTester tester,
      {ValueChanged<String>? onFiled,
      VoidCallback? onExit,
      _RecordingFlagService? flag}) async {
    final bloc = LocalWarRoomBloc(repository: InMemoryWarCaseRepository());
    await tester.pumpWidget(MaterialApp(
      home: WarRoomIntakeScreen(
        bloc: bloc,
        onFiled: onFiled,
        onExit: onExit,
        secureFlagService: flag,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }
    return bloc;
  }

  Future<void> completeFlow(WidgetTester tester) async {
    // Step 1 — situation.
    await tester.tap(find.text('I am being blackmailed or extorted'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();

    // Step 2 — narrative.
    await tester.enterText(
        find.byType(TextField), 'They have my photos and want money.');
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();

    // Step 3 — evidence (optional, Continue enabled).
    await tester.tap(find.text('Continue →'));
    await tester.pump();

    // Step 4 — urgency.
    await tester.tap(find.text('This needs attention soon (this week)'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();

    // Step 5 — consent.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
  }

  group('WarRoomIntakeScreen (Task 8.1)', () {
    testWidgets('FLAG_SECURE is enabled on the intake flow', (tester) async {
      final flag = _RecordingFlagService();
      await pump(tester, flag: flag);
      expect(flag.enableCalls, greaterThanOrEqualTo(1));
    });

    testWidgets('Continue is gated until each step is complete',
        (tester) async {
      await pump(tester);

      // Step 1: nothing selected → disabled.
      final continueBtn = find.widgetWithText(FilledButton, 'Continue →');
      expect(
        tester.widget<FilledButton>(continueBtn).onPressed,
        isNull,
      );

      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      expect(
        tester.widget<FilledButton>(continueBtn).onPressed,
        isNotNull,
      );
    });

    testWidgets('steps walk 1 → 5 with progress dots and Back', (tester) async {
      await pump(tester);
      expect(find.text('STEP 1 OF 5 — SITUATION OVERVIEW'), findsOneWidget);

      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      expect(find.text('STEP 2 OF 5 — YOUR SITUATION'), findsOneWidget);

      // Back returns to step 1.
      await tester.tap(find.text('Back'));
      await tester.pump();
      expect(find.text('STEP 1 OF 5 — SITUATION OVERVIEW'), findsOneWidget);
    });

    testWidgets('evidence step shows the encrypted-before-leaving notice',
        (tester) async {
      await pump(tester);
      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), 'Narrative text here.');
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();

      expect(find.text('STEP 3 OF 5 — EVIDENCE'), findsOneWidget);
      expect(
        find.textContaining('Evidence is encrypted before leaving your device'),
        findsOneWidget,
      );
    });

    testWidgets('full flow files the case and reports the stamp',
        (tester) async {
      _setTallViewport(tester);
      String? filedStamp;
      final bloc = await pump(tester, onFiled: (s) => filedStamp = s);

      await completeFlow(tester);
      await tester.tap(find.text('Submit case securely'));
      await tester.pump();
      await tester.pump();

      expect(filedStamp, 'CC-0001',
          reason: 'extortion + this-week → sequential stamp CC-0001');
      await bloc.close();
    });

    testWidgets('close icon fires onExit', (tester) async {
      var exited = false;
      await pump(tester, onExit: () => exited = true);
      await tester.tap(find.byIcon(Icons.close));
      expect(exited, isTrue);
    });
  });

  group('WarRoomIntakeScreen evidence (Task 8.2)', () {
    Future<void> gotoEvidenceStep(WidgetTester tester) async {
      await tester.tap(find.text('I am being blackmailed or extorted'));
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), 'They have my photos and want money.');
      await tester.pump();
      await tester.tap(find.text('Continue →'));
      await tester.pump();
      expect(find.text('STEP 3 OF 5 — EVIDENCE'), findsOneWidget);
    }

    testWidgets('picking a file attaches a mime·size chip (no filename)',
        (tester) async {
      final picker = _FakePicker([
        PickedEvidence(
          bytes: Uint8List.fromList(List.generate(2048, (i) => i & 0xff)),
          displayName: 'victim_pan_card.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 2048,
        ),
      ]);
      final sink = _FakeEvidenceSink();
      final bloc = LocalWarRoomBloc(
        repository: InMemoryWarCaseRepository(),
        evidenceSink: sink,
      );
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          picker: picker,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      await gotoEvidenceStep(tester);

      await tester.tap(find.text('Add evidence'));
      await tester.pump();
      await tester.pump();

      // The derived label renders — the raw filename NEVER does.
      expect(find.text('Photo · 2.0 KB'), findsOneWidget);
      expect(find.textContaining('pan_card'), findsNothing);
      expect(find.textContaining('victim'), findsNothing);
      expect(find.text('ENCRYPTED'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('cancelling the picker adds nothing', (tester) async {
      final picker = _FakePicker(); // empty queue → null (cancel)
      final bloc = LocalWarRoomBloc(
        repository: InMemoryWarCaseRepository(),
        evidenceSink: _FakeEvidenceSink(),
      );
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          picker: picker,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      await gotoEvidenceStep(tester);

      await tester.tap(find.text('Add evidence'));
      await tester.pump();
      await tester.pump();

      expect(picker.calls, 1);
      expect(find.textContaining('Photo'), findsNothing);
      await bloc.close();
    });

    testWidgets('evidence failure shows a generic banner, flow survives',
        (tester) async {
      final picker = _FakePicker([
        PickedEvidence(
          bytes: Uint8List.fromList([1, 2, 3]),
          displayName: 'a.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 3,
        ),
      ]);
      final failing = _FailingEvidenceSink();
      final bloc = LocalWarRoomBloc(
        repository: InMemoryWarCaseRepository(),
        evidenceSink: failing,
      );
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          picker: picker,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      await gotoEvidenceStep(tester);

      await tester.tap(find.text('Add evidence'));
      await tester.pump();
      await tester.pump();

      expect(
        find.textContaining('Could not encrypt this file'),
        findsOneWidget,
        reason: 'a fixed generic message — never a stack trace',
      );
      // The flow still works — Continue remains enabled (evidence optional).
      expect(
        tester
            .widget<FilledButton>(
                find.widgetWithText(FilledButton, 'Continue →'))
            .onPressed,
        isNotNull,
      );
      await bloc.close();
    });

    testWidgets('FLAG_SECURE still fires with evidence attached',
        (tester) async {
      final flag = _RecordingFlagService();
      final picker = _FakePicker([
        PickedEvidence(
          bytes: Uint8List.fromList([7, 7, 7]),
          displayName: 'clip.jpg',
          mimeType: 'video/mp4',
          sizeBytes: 7,
        ),
      ]);
      final bloc = LocalWarRoomBloc(
        repository: InMemoryWarCaseRepository(),
        evidenceSink: _FakeEvidenceSink(),
      );
      await tester.pumpWidget(MaterialApp(
        home: WarRoomIntakeScreen(
          bloc: bloc,
          picker: picker,
          secureFlagService: flag,
        ),
      ));
      await gotoEvidenceStep(tester);
      await tester.tap(find.text('Add evidence'));
      await tester.pump();
      await tester.pump();
      expect(flag.enableCalls, greaterThanOrEqualTo(1));
      await bloc.close();
    });
  });
}

class _FailingEvidenceSink implements EvidenceSink {
  @override
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence) async {
    throw StateError('boom');
  }

  @override
  Future<List<EvidenceRecord>> localEvidence() async => [];

  @override
  Future<void> removeEvidence(String evidenceId) async {}
}
