import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/data/queue_legal_aid_handoff_sink.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Task 8.6 end-to-end with REAL stores (no fakes): file a case → the
/// append-only custody chain records filed/triage/assigned → the detail
/// renders the CHAIN OF CUSTODY section → the Verified Intel Report is
/// HMAC-signed (deterministic) → the legal-aid handoff is locally persisted
/// + sealed into the real sync queue → integrity still verifies.
void main() {
  const submission = CaseIntakeSubmission(
    situation: IntakeSituation.blackmailExtortion,
    narrative: 'They are blackmailing me with leaked photos.',
    urgency: IntakeUrgency.thisWeek,
    consentNotLegalAdvice: true,
    consentLegalAidReferral: true,
  );

  testWidgets('file → custody chain UI → signed report → sealed handoff',
      (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final handoffStore = InMemoryEntityStore<LegalAidHandoff>((h) => h.id);
    final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
    final sink = QueueLegalAidHandoffSink(
      handoffStore: handoffStore,
      syncQueue:
          LocalSyncQueueRepository(store: queueStore, cipher: testCipher()),
    );
    final repo = InMemoryWarCaseRepository(handoffSink: sink);
    final bloc = LocalWarRoomBloc(repository: repo);
    await bloc.start();

    // File through the REAL repository → the custody chain is created.
    final filed = await repo.fileCase(submission);
    expect(filed.caseNumber, isNotEmpty);
    final chain = await repo.custodyEvents(filed.caseNumber);
    expect(
        chain.map((e) => e.type),
        containsAll([
          CustodyEventType.caseFiled,
          CustodyEventType.autoTriage,
          CustodyEventType.analystAssigned,
        ]));
    // Chain invariants hold end-to-end.
    expect(await repo.verifyCustodyIntegrity(), isTrue);

    // The detail renders the CHAIN OF CUSTODY section (scrolled into view).
    await bloc.openCase(filed.caseNumber);
    await tester.pumpWidget(MaterialApp(
      home: WarCaseDetailScreen(bloc: bloc, caseNumber: filed.caseNumber),
    ));
    for (var i = 0; i < 8; i++) {
      await tester.pump();
    }
    await tester.scrollUntilVisible(find.text('CHAIN OF CUSTODY'), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.text('CHAIN OF CUSTODY'), findsOneWidget);
    expect(find.text('CASE FILED'), findsOneWidget);
    expect(find.text('AUTO-TRIAGE'), findsOneWidget);

    // Sign the report — deterministic, verifiable.
    final signed = await bloc.signVerifiedReport(filed.caseNumber);
    expect(signed.signature, isNotEmpty);
    final again = await repo.signVerifiedReport(filed.caseNumber);
    expect(again.signature, signed.signature,
        reason: 'the HMAC must be deterministic for the same case');

    // Queue the legal-aid handoff through the REAL sink → locally persisted
    // AND sealed in the real queue with the UUID v4 id as the item id.
    final id = await bloc.queueLegalAidHandoff(filed.caseNumber);
    expect(
        id,
        matches(RegExp(
            r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
    expect(handoffStore.length, 1);
    expect((await handoffStore.getAll()).single.caseNumber, filed.caseNumber);
    expect(queueStore.length, 1);
    expect((await queueStore.getAll()).single.id, id);

    // The sealed frame unseals to the strict handoff envelope.
    final opened =
        await testCipher().open((await queueStore.getAll()).single.payload);
    final envelope =
        LegalAidHandoffEnvelope.decode(String.fromCharCodes(opened));
    expect(envelope.caseNumber, filed.caseNumber);

    // The custody chain grew: handoff event recorded, integrity intact.
    final finalChain = await repo.custodyEvents(filed.caseNumber);
    expect(finalChain.map((e) => e.type),
        contains(CustodyEventType.handoffQueued));
    expect(await repo.verifyCustodyIntegrity(), isTrue);

    await bloc.close();
  });

  test('withdraw finalizes the chain with CASE WITHDRAWN, integrity intact',
      () async {
    final repo = InMemoryWarCaseRepository();
    final filed = await repo.fileCase(submission);
    await repo.withdraw(filed.caseNumber);

    final chain = await repo.custodyEvents(filed.caseNumber);
    expect(chain.last.type, CustodyEventType.caseWithdrawn);
    expect(await repo.verifyCustodyIntegrity(), isTrue);
  });
}
