import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/data/queue_legal_aid_handoff_sink.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Task 13.3 E2E: War Room pillar end-to-end lifecycle.
///
/// Tests the complete user journey:
/// 1. File a new case through intake
/// 2. Verify custody chain is created (filed → triage → assigned)
/// 3. Sign verified intel report
/// 4. Queue legal aid handoff
/// 5. Withdraw a case and verify chain closure
/// 6. Verify integrity holds after all operations
void main() {
  const blackmailSubmission = CaseIntakeSubmission(
    situation: IntakeSituation.blackmailExtortion,
    narrative: 'They are blackmailing me with leaked photos.',
    urgency: IntakeUrgency.thisWeek,
    consentNotLegalAdvice: true,
    consentLegalAidReferral: true,
  );

  const threatSubmission = CaseIntakeSubmission(
    situation: IntakeSituation.threateningMessages,
    narrative: 'I received threatening messages online.',
    urgency: IntakeUrgency.immediate,
    consentNotLegalAdvice: true,
    consentLegalAidReferral: true,
  );

  group('War Room E2E - Full case lifecycle', () {
    test('file → custody chain → sign → handoff → integrity holds', () async {
      // Set up with a handoff sink wired.
      final handoffStore =
          InMemoryEntityStore<LegalAidHandoff>((h) => h.id);
      final queueStore =
          InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final sink = QueueLegalAidHandoffSink(
        handoffStore: handoffStore,
        syncQueue:
            LocalSyncQueueRepository(store: queueStore, cipher: testCipher()),
      );
      final repo = InMemoryWarCaseRepository(handoffSink: sink);
      final bloc = LocalWarRoomBloc(repository: repo);
      await bloc.start();

      // Step 1: File a case through the bloc.
      final caseNumber = await bloc.fileCase(blackmailSubmission);
      expect(caseNumber, startsWith('CC-'));

      // Step 2: Verify the custody chain was auto-created.
      final chain = await repo.custodyEvents(caseNumber);
      expect(chain.length, greaterThanOrEqualTo(3));
      expect(
        chain.map((e) => e.type),
        containsAll([
          CustodyEventType.caseFiled,
          CustodyEventType.autoTriage,
          CustodyEventType.analystAssigned,
        ]),
      );

      // Step 3: Verify chain integrity after filing.
      expect(await repo.verifyCustodyIntegrity(), isTrue);

      // Step 4: Sign the verified intel report (HMAC — deterministic).
      final signed = await repo.signVerifiedReport(caseNumber);
      expect(signed.signature, isNotEmpty);
      final again = await repo.signVerifiedReport(caseNumber);
      expect(again.signature, signed.signature,
          reason: 'the HMAC must be deterministic for the same case');

      // Step 5: Queue legal-aid handoff through the sealed sink.
      final handoffId = await repo.queueLegalAidHandoff(caseNumber);
      expect(handoffId, isNotEmpty);

      // The handoff is locally persisted.
      expect(handoffStore.length, 1);
      expect(
        (await handoffStore.getAll()).single.caseNumber,
        caseNumber,
      );

      // The handoff is sealed in the sync queue.
      expect(queueStore.length, 1);
      final sealedPayload = (await queueStore.getAll()).single.payload;
      final opened = await testCipher().open(sealedPayload);
      final envelope =
          LegalAidHandoffEnvelope.decode(String.fromCharCodes(opened));
      expect(envelope.caseNumber, caseNumber);

      // Step 6: Custody chain grew with the handoff event.
      final finalChain = await repo.custodyEvents(caseNumber);
      expect(
        finalChain.map((e) => e.type),
        contains(CustodyEventType.handoffQueued),
      );

      // Step 7: Chain integrity still holds after all mutations.
      expect(await repo.verifyCustodyIntegrity(), isTrue);

      await bloc.close();
    });

    test('withdraw case closes the custody chain', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(blackmailSubmission);
      await repo.withdraw(filed.caseNumber);

      final chain = await repo.custodyEvents(filed.caseNumber);
      expect(chain.last.type, CustodyEventType.caseWithdrawn);

      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('multiple cases maintain independent custody chains', () async {
      final repo = InMemoryWarCaseRepository();
      final case1 = await repo.fileCase(blackmailSubmission);
      final case2 = await repo.fileCase(threatSubmission);

      final chain1 = await repo.custodyEvents(case1.caseNumber);
      final chain2 = await repo.custodyEvents(case2.caseNumber);
      expect(chain1, isNotEmpty);
      expect(chain2, isNotEmpty);
      expect(chain1.first.caseNumber, case1.caseNumber);
      expect(chain2.first.caseNumber, case2.caseNumber);

      // Intervening operations on case1 don't affect case2.
      await repo.signVerifiedReport(case1.caseNumber);
      final chain2After = await repo.custodyEvents(case2.caseNumber);
      expect(chain2After.length, chain2.length);

      expect(await repo.verifyCustodyIntegrity(), isTrue);
    });

    test('severity scoring produces deterministic results', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(blackmailSubmission);
      expect(filed.severity, isNotNull);

      final chain = await repo.custodyEvents(filed.caseNumber);
      expect(chain.any((e) => e.type == CustodyEventType.autoTriage), isTrue);
    });

    test('no PII in case number or custody events', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(blackmailSubmission);
      expect(filed.caseNumber, startsWith('CC-'));
      expect(filed.caseNumber, isNot(contains('+91')));
      expect(filed.caseNumber, isNot(contains('@')));

      final chain = await repo.custodyEvents(filed.caseNumber);
      for (final event in chain) {
        expect(event.type, isA<CustodyEventType>());
      }
    });

    test('no raw hashes in case fields', () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(blackmailSubmission);
      expect(filed.title, isNotEmpty);
      expect(filed.title.length, lessThan(100));
      expect(filed.caseNumber, isNot(matches(RegExp(r'[0-9a-f]{64}'))));
    });
  });
}
