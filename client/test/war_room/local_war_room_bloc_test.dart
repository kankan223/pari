import 'dart:async';
import 'dart:typed_data';

import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/domain/war_room_state.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:civic_commons/war_room/domain/evidence_item.dart';
import 'package:civic_commons/war_room/domain/evidence_ports.dart';
import 'package:civic_commons/war_room/domain/severity_scoring.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  WarRoomCase makeCase(String stamp) => WarRoomCase(
        caseNumber: stamp,
        title: 'Fake social media profile — identity theft',
        description: 'd',
        severity: CaseSeverity.medium,
        status: CaseStatus.underInvestigation,
        filedAt: t0,
      );

  CaseIntakeSubmission submission() => const CaseIntakeSubmission(
        situation: IntakeSituation.threateningMessages,
        narrative: 'They keep threatening me.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      );

  group('LocalWarRoomBloc (Task 8.1)', () {
    test('start emits the loaded case list', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);

      await bloc.start();
      await capture.settle();

      expect(capture.last?.status, WarRoomStatus.loaded);
      expect(capture.last?.cases, hasLength(1));
      expect(capture.last!.cases.first.caseNumber, 'CC-0001');

      await capture.close();
    });

    test('openCase selects the case; closeCase clears it', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      await bloc.openCase('CC-0001');
      await capture.settle();
      expect(capture.last?.selected?.caseNumber, 'CC-0001');

      await bloc.closeCase();
      await capture.settle();
      expect(capture.last?.selected, isNull);

      await capture.close();
    });

    test('fileCase returns the stamp and the list gains the case', () async {
      final repo = InMemoryWarCaseRepository();
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      final stamp = await bloc.fileCase(submission());
      expect(stamp, 'CC-0001');
      await capture.settle();

      expect(capture.last!.cases, hasLength(1));
      expect(capture.last!.cases.first.caseNumber, stamp);
      // Task 8.4: the deterministic keyword engine replaces the provisional
      // hint — this narrative is auto-scored HIGH (threats + money) above
      // the situation category's MEDIUM provisional.
      expect(capture.last!.cases.first.severity, CaseSeverity.high);
      expect(capture.last!.cases.first.triage, isNotNull);
      expect(capture.last!.cases.first.estReportHours, 48);

      await capture.close();
    });

    test('setPaused and withdraw reflect in the emitted state', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      await bloc.setPaused('CC-0001', true);
      await capture.settle();
      expect(capture.last!.cases.first.paused, isTrue);

      await bloc.withdraw('CC-0001');
      await capture.settle();
      expect(capture.last!.cases.first.status, CaseStatus.withdrawn);
      expect(capture.last!.cases.first.paused, isFalse,
          reason: 'withdraw clears the pause marker');

      await capture.close();
    });

    test('open detail follows pause/withdraw on refresh', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();
      await bloc.openCase('CC-0001');
      await bloc.withdraw('CC-0001');
      await capture.settle();
      expect(capture.last!.selected?.status, CaseStatus.withdrawn,
          reason: 'the open detail view must track store mutations');
      await capture.close();
    });
  });

  group('LocalWarRoomBloc evidence (Task 8.2)', () {
    PickedEvidence picked() => PickedEvidence(
          bytes: Uint8List.fromList(List.generate(512, (i) => i & 0xff)),
          displayName: 'photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: 512,
        );

    test('attachEvidence emits a UI-safe EvidenceSummary', () async {
      final repo = InMemoryWarCaseRepository();
      final evidenceStore = _FakeEvidenceStore();
      final sink = _RecordingEvidenceSink(evidenceStore);
      final bloc = LocalWarRoomBloc(repository: repo, evidenceSink: sink);
      final capture = Capture(bloc);
      await bloc.start();

      final id = await bloc.attachEvidence('DRAFT-x', picked());
      await capture.settle();

      expect(sink.added, 1);
      expect(id, isNotEmpty);
      final evidence = capture.last!.evidence;
      expect(evidence, hasLength(1));
      expect(evidence.single.id, id);
      expect(evidence.single.caseNumber, 'DRAFT-x');
      expect(evidence.single.mimeType, 'image/jpeg');
      expect(evidence.single.sizeBytes, 512);
      // NO filename, no path, no identity in the summary.
      expect(evidence.single.toString(), isNot(contains('photo')));
      expect(capture.last!.encryptingEvidence, isFalse);
      expect(capture.last!.evidenceError, isNull);

      await capture.close();
    });

    test('sink failure degrades to a GENERIC error and never crashes',
        () async {
      final repo = InMemoryWarCaseRepository();
      final sink = _FailingEvidenceSink();
      final bloc = LocalWarRoomBloc(repository: repo, evidenceSink: sink);
      final capture = Capture(bloc);
      await bloc.start();

      await expectLater(
        bloc.attachEvidence('DRAFT-x', picked()),
        throwsA(anything),
      );
      await capture.settle();

      expect(capture.last!.evidence, isEmpty);
      expect(capture.last!.encryptingEvidence, isFalse);
      expect(
        capture.last!.evidenceError,
        contains('Could not encrypt this file'),
        reason: 'a fixed generic message, never a stack trace or internals',
      );
      expect(
        capture.last!.evidenceError,
        isNot(contains('StateError')),
        reason: 'no exception type may leak',
      );

      await capture.close();
    });

    test('no sink configured → generic error, no crash', () async {
      final repo = InMemoryWarCaseRepository();
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      await expectLater(
        bloc.attachEvidence('DRAFT-x', picked()),
        throwsA(isA<StateError>()),
      );
      await capture.settle();
      expect(capture.last!.evidenceError, isNotNull);

      await capture.close();
    });

    test('overrideSeverity re-bands the emitted case summary', () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      await bloc.overrideSeverity(
        'CC-0001',
        SeverityOverride(
          newSeverity: CaseSeverity.low,
          reason: 'no credible threat',
          at: t0,
        ),
      );
      await capture.settle();

      expect(capture.last!.cases.first.severity, CaseSeverity.low);
      expect(capture.last!.cases.first.estReportHours, 120);
      expect(capture.last!.cases.first.severityOverride, isNotNull);
      await capture.close();
    });

    test('addAnalystUpdate emits a case carrying the blinded note', () async {
      final repo = InMemoryWarCaseRepository();
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();

      final filed = await repo.fileCase(submission());
      final analystId = filed.assignments.first.analystId;
      await bloc.addAnalystUpdate(
        filed.caseNumber,
        analystId,
        'Verified the account origin.',
        'In progress',
      );
      await capture.settle();

      final caseSummary = capture.last!.cases
          .firstWhere((c) => c.caseNumber == filed.caseNumber);
      expect(caseSummary.updates.single.analystId, analystId);
      expect(caseSummary.updates.single.text, contains('Verified'));
      expect(caseSummary.assignments, isNotEmpty,
          reason: 'the summary must carry the blinded team');
      await capture.close();
    });

    test('refreshEvidence reloads persisted evidence after cold start',
        () async {
      final repo = InMemoryWarCaseRepository();
      final evidenceStore = _FakeEvidenceStore();
      final sink = _RecordingEvidenceSink(evidenceStore);
      final bloc = LocalWarRoomBloc(repository: repo, evidenceSink: sink);
      final capture = Capture(bloc);
      await bloc.start();

      await bloc.attachEvidence('DRAFT-x', picked());
      // Simulate a cold restart: a NEW bloc reads the same store.
      final bloc2 = LocalWarRoomBloc(repository: repo, evidenceSink: sink);
      final capture2 = Capture(bloc2);
      await bloc2.start();
      await capture2.settle();
      expect(capture2.last!.evidence, isEmpty,
          reason: 'evidence is not loaded until refreshEvidence()');

      await bloc2.refreshEvidence();
      await capture2.settle();
      expect(capture2.last!.evidence, hasLength(1));
      expect(capture2.last!.evidence.single.mimeType, 'image/jpeg');

      await capture.close();
      await capture2.close();
    });
  });

  group('LocalWarRoomBloc · Task 8.6 custody + report', () {
    test('signVerifiedReport returns the signed report and refreshes state',
        () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();
      await bloc.openCase('CC-0001');
      await capture.settle();

      final signed = await bloc.signVerifiedReport('CC-0001');
      await capture.settle();

      expect(signed.report.caseNumber, 'CC-0001');
      expect(signed.signature, isNotEmpty);
      // The custody chain is attached to the selected case summary.
      final selected = capture.last?.selected;
      expect(selected, isNotNull);
      expect(selected!.custodyEvents, isNotEmpty);
      expect(selected.custodyEvents.map((e) => e.type),
          contains(CustodyEventType.reportSigned));

      await capture.close();
    });

    test('queueLegalAidHandoff returns an id and refreshes the custody chain',
        () async {
      final repo = InMemoryWarCaseRepository(seed: [makeCase('CC-0001')]);
      final bloc = LocalWarRoomBloc(repository: repo);
      final capture = Capture(bloc);
      await bloc.start();
      await bloc.openCase('CC-0001');
      await capture.settle();

      final id = await bloc.queueLegalAidHandoff('CC-0001');
      await capture.settle();

      expect(id, isNotEmpty);
      final selected = capture.last?.selected;
      expect(selected!.custodyEvents.map((e) => e.type),
          contains(CustodyEventType.handoffQueued));

      await capture.close();
    });
  });
}

/// In-memory evidence store fake (mirrors the row shape).
class _FakeEvidenceStore {
  final Map<String, EvidenceRecord> _rows = {};

  Future<void> put(EvidenceRecord r) async => _rows[r.id] = r;
  Future<List<EvidenceRecord>> all() async => _rows.values.toList();
}

class _RecordingEvidenceSink implements EvidenceSink {
  final _FakeEvidenceStore store;
  int added = 0;

  _RecordingEvidenceSink(this.store);

  @override
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence) async {
    added++;
    final id = 'ev-${added.toString().padLeft(4, '0')}';
    final record = EvidenceRecord(
      id: id,
      caseNumber: caseNumber,
      sealedFile: Uint8List.fromList([1, 2, 3]),
      dekEnvelope: Uint8List.fromList([4, 5, 6]),
      sizeBytes: evidence.sizeBytes,
      mimeType: evidence.mimeType,
      createdAt: DateTime.utc(2026, 8, 12),
    );
    await store.put(record);
    return id;
  }

  @override
  Future<List<EvidenceRecord>> localEvidence() => store.all();

  @override
  Future<void> removeEvidence(String evidenceId) async {
    throw UnimplementedError();
  }
}

class _FailingEvidenceSink implements EvidenceSink {
  @override
  Future<String> addEvidence(String caseNumber, PickedEvidence evidence) async {
    throw StateError('disk is on fire');
  }

  @override
  Future<List<EvidenceRecord>> localEvidence() async => [];

  @override
  Future<void> removeEvidence(String evidenceId) async {}
}

/// A capture harness for the broadcast state stream: subscribes once and
/// records every emission (broadcast streams do not replay).
class Capture {
  final LocalWarRoomBloc bloc;
  late final StreamSubscription<WarRoomState> sub;
  WarRoomState? last;

  Capture(LocalWarRoomBloc repository) : bloc = repository {
    sub = repository.state.listen((s) => last = s);
  }

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  Future<void> close() async {
    await sub.cancel();
    await bloc.close();
  }
}
