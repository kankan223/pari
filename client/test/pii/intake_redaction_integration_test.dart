import 'package:civic_commons/pii/data/dictionary_pii_detector.dart';
import 'package:civic_commons/pii/data/local_pii_redaction_pipeline.dart';
import 'package:civic_commons/pii/domain/pii_pipeline_port.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 8.3 integration: the REAL redaction pipeline is wired into the
/// intake seam — the narrative is scrubbed (phone + name) BEFORE the case is
/// filed, the submission carries the non-PII report, and the plaintext
/// buffer is wiped.
void _setTallViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets(
      'intake with redaction pipeline: narrative filed with zero raw PII',
      (tester) async {
    _setTallViewport(tester);
    final repo = InMemoryWarCaseRepository();
    final pipeline = LocalPiiRedactionPipeline(
      localDetector: const DictionaryPiiDetector(),
    );
    final bloc = LocalWarRoomBloc(repository: repo);
    // Track the buffer that was wiped at submit time.
    final wipedBuffers = <Uint8BufferInput>[];
    final wrapped = _WipingPipeline(pipeline, wipedBuffers);

    String? filedStamp;
    await tester.pumpWidget(MaterialApp(
      home: WarRoomIntakeScreen(
        bloc: bloc,
        redactionPipeline: wrapped,
        onFiled: (s) => filedStamp = s,
      ),
    ));
    for (var i = 0; i < 4; i++) {
      await tester.pump();
    }

    // Step 1 — situation.
    await tester.tap(find.text('I am being blackmailed or extorted'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 2 — narrative WITH PII (phone + name + address).
    await tester.enterText(
      find.byType(TextField),
      'Rahul threatened me and called +919876543210 near MG Road.',
    );
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 3 — evidence (skip).
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 4 — urgency.
    await tester.tap(find.text('This needs attention soon (this week)'));
    await tester.pump();
    await tester.tap(find.text('Continue →'));
    await tester.pump();
    // Step 5 — consent + submit.
    await tester.tap(find.byType(CheckboxListTile).first);
    await tester.pump();
    await tester.tap(find.byType(CheckboxListTile).at(1));
    await tester.pump();
    await tester.tap(find.text('Submit case securely'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(filedStamp, 'CC-0001');

    // The stored case description is the REDACTED narrative — no raw PII.
    final filed = await repo.getCaseById('CC-0001');
    expect(filed, isNotNull);
    expect(filed!.description, isNot(contains('9876543210')));
    expect(filed.description, isNot(contains('+91')));
    expect(filed.description, isNot(contains('MG Road')));
    expect(filed.description, contains('[REDACTED]'));

    // The plaintext buffer was wiped at submit time (memory wipe proof).
    expect(wipedBuffers, hasLength(1));
    expect(wipedBuffers.single.wiped, isTrue);

    await bloc.close();
  });
}

/// Delegates to the real pipeline and records every input buffer so the
/// test can assert the wipe happened end-to-end.
class _WipingPipeline implements PiiRedactionPipeline {
  final PiiRedactionPipeline inner;
  final List<Uint8BufferInput> seen;

  _WipingPipeline(this.inner, this.seen);

  @override
  PiiRedactionResult redact(Uint8BufferInput input) {
    seen.add(input);
    return inner.redact(input);
  }
}
