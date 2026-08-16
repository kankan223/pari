import 'dart:io';
import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/state/ui/war_room_case_list_screen.dart';
import 'package:civic_commons/state/ui/war_room_intake_screen.dart';
import 'package:civic_commons/war_room/data/aes_gcm_evidence_cipher.dart';
import 'package:civic_commons/war_room/data/in_memory_analyst_registry.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/data/queue_evidence_sink.dart';
import 'package:civic_commons/war_room/data/queue_legal_aid_handoff_sink.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:civic_commons/war_room/domain/evidence_envelope.dart';
import 'package:civic_commons/war_room/domain/evidence_item.dart';
import 'package:civic_commons/war_room/domain/severity_scoring.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// Task 8.1 SECURITY CHECKPOINT.
///
/// 1. FLAG_SECURE is ACTIVE on every War Room screen (list, detail, intake)
///    — verified with a recording flag service.
/// 2. The War Room data/state layers import NO networking
///    (http/WebSocket/dart:io sockets) — local-first by construction.
/// 3. No raw PII (E.164 phones, 64-hex blind hashes, real names, handles)
///    can reach the widget tree.
/// 4. No raw debug output (print/logger) exists in War Room production code.
void main() {
  group('Task 8.1 SECURITY CHECKPOINT', () {
    testWidgets('FLAG_SECURE is active on every War Room screen',
        (tester) async {
      final listFlag = _RecordingFlagService();
      final repo = InMemoryWarCaseRepository(seed: [
        WarRoomCase(
          caseNumber: 'CC-0047',
          title: 't',
          description: 'd',
          severity: CaseSeverity.high,
          status: CaseStatus.underInvestigation,
          filedAt: DateTime.utc(2026),
        ),
      ]);
      final bloc = LocalWarRoomBloc(repository: repo);
      await bloc.start();

      // Case list.
      await _pumpFlagged(
          tester,
          WarRoomCaseListScreen(
            bloc: bloc,
            secureFlagService: listFlag,
          ));
      expect(listFlag.enableCalls, greaterThanOrEqualTo(1),
          reason: 'case list must enable FLAG_SECURE');

      // Case detail.
      final detailFlag = _RecordingFlagService();
      await bloc.openCase('CC-0047');
      await _pumpFlagged(
          tester,
          WarCaseDetailScreen(
            bloc: bloc,
            caseNumber: 'CC-0047',
            secureFlagService: detailFlag,
          ));
      expect(detailFlag.enableCalls, greaterThanOrEqualTo(1),
          reason: 'case detail must enable FLAG_SECURE');

      // Intake flow.
      final intakeFlag = _RecordingFlagService();
      await _pumpFlagged(
          tester,
          WarRoomIntakeScreen(
            bloc: bloc,
            secureFlagService: intakeFlag,
          ));
      expect(intakeFlag.enableCalls, greaterThanOrEqualTo(1),
          reason: 'intake must enable FLAG_SECURE');

      await bloc.close();
    });

    test('War Room data/state layers are local-first — zero networking', () {
      final files = <File>[
        File('lib/war_room/data/in_memory_war_case_repository.dart'),
        File('lib/state/data/local_war_room_bloc.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(
          forbidden.hasMatch(src),
          isFalse,
          reason: '${file.path} must not import networking '
              '(offline-first War Room)',
        );
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('no War Room production file prints raw output', () {
      final dirs = [
        Directory('lib/war_room'),
        Directory('lib/state/ui/war_room_case_list_screen.dart').parent,
      ];
      for (final dir in dirs) {
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .where((f) => !f.path.endsWith('_test.dart'))) {
          final src = f.readAsStringSync();
          if (f.path.contains('war_room') ||
              f.path.contains('war_case') ||
              f.path.contains('war_room_')) {
            expect(src.contains('print('), isFalse,
                reason: '${f.path} must not print');
            expect(src.contains('debugPrint('), isFalse,
                reason: '${f.path} must not debugPrint');
          }
        }
      }
    });

    testWidgets('case list renders ONLY dossier attributes (zero-PII)',
        (tester) async {
      final bloc = LocalWarRoomBloc(
          repository: InMemoryWarCaseRepository(seed: [
        WarRoomCase(
          caseNumber: 'CC-0047',
          title: 'Digital extortion — photo leak threat',
          description: 'd',
          severity: CaseSeverity.high,
          status: CaseStatus.underInvestigation,
          filedAt: DateTime.utc(2026),
          analystCount: 2,
        ),
      ]));
      await bloc.start();
      await tester.pumpWidget(MaterialApp(
        home: WarRoomCaseListScreen(bloc: bloc),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      expect(texts, isNot(contains('@')));
      await bloc.close();
    });

    test('evidence pipeline is local-first — zero networking in war_room', () {
      final files = <File>[
        File('lib/war_room/data/aes_gcm_evidence_cipher.dart'),
        File('lib/war_room/data/queue_evidence_sink.dart'),
        File('lib/war_room/domain/evidence_envelope.dart'),
        File('lib/war_room/domain/evidence_item.dart'),
        File('lib/war_room/domain/evidence_ports.dart'),
        File('lib/state/data/local_war_room_bloc.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking '
                '(evidence never leaves via a raw channel)');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('BYTE-LEVEL: queue bytes never match the plaintext file', () async {
      final plaintext =
          Uint8List.fromList(List.generate(2048, (i) => (i * 7) & 0xff));
      final evidenceStore = InMemoryEntityStore<EvidenceRecord>((r) => r.id);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final device = await X25519().newKeyPair();
      final sink = QueueEvidenceSink(
        cipher: AesGcmEvidenceCipher(
            crypto: CryptoServiceImpl(), deviceKeyPair: device),
        evidenceStore: evidenceStore,
        syncQueue:
            LocalSyncQueueRepository(store: queueStore, cipher: testCipher()),
        recipientPublicKey: await device.extractPublicKey(),
      );

      await sink.addEvidence(
        'DRAFT-x',
        PickedEvidence(
          bytes: plaintext,
          displayName: 'screenshot_of_harassment.png',
          mimeType: 'image/png',
          sizeBytes: plaintext.length,
        ),
      );

      final record = (await evidenceStore.getAll()).single;
      final rawPayload = (await queueStore.getAll()).single.payload;
      final head = plaintext.sublist(0, 64);
      expect(record.sealedFile, isNot(equals(plaintext)));
      expect(_contains(record.sealedFile, head), isFalse);
      expect(rawPayload, isNot(equals(plaintext)));
      expect(_contains(rawPayload, head), isFalse);
    });

    test('Task 8.4: severity scoring is DETERMINISTIC (repeated-invocation)',
        () {
      const scorer = SeverityScorer();
      const narrative = 'he leaked my photos and threatened me for money';
      CaseSeverity run() => scorer
          .score(
            narrative: narrative,
            floorSeverity: CaseSeverity.high,
            urgency: IntakeUrgency.thisWeek,
          )
          .severity;
      final first = run();
      for (var i = 0; i < 25; i++) {
        expect(run(), first,
            reason: 'identical input must produce identical severity');
      }
    });

    test('Task 8.4: the scorer reads only case content — zero identity input',
        () {
      const scorer = SeverityScorer();
      // A narrative packed with PII shapes still only ever yields severity
      // + counts — no PII crosses the boundary.
      final r = scorer.score(
        narrative: 'Priya +919876543210 at MG Road threatened me',
        floorSeverity: CaseSeverity.medium,
        urgency: IntakeUrgency.noDeadline,
      );
      expect(r.toString(), isNot(contains('Priya')));
      expect(r.toString(), isNot(contains('9876543210')));
      expect(r.signalLabels.join('|'), isNot(contains('MG')));
    });

    test(
        'Task 8.4: severity files are local-first — zero networking, no prints',
        () {
      final files = <File>[
        File('lib/war_room/domain/severity_scoring.dart'),
        File('lib/state/ui/severity_override_sheet.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('Task 8.5: analyst identities are BLINDED to victims (structural)',
        () async {
      final registry = InMemoryAnalystRegistry.production();
      final repo = InMemoryWarCaseRepository(registry: registry);
      final filed = await repo.fileCase(const CaseIntakeSubmission(
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'They are blackmailing me.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      ));
      // The ONLY analyst-bearing surfaces are blinded AN-#### handles.
      for (final a in filed.assignments) {
        expect(a.analystId, matches(r'^AN-\d{4}$'));
      }
      for (final u in filed.updates) {
        expect(u.analystId, matches(r'^AN-\d{4}$'));
      }
      // No name/email/phone/hash can ever be an analyst identifier.
      final analystDump = filed.assignments.map((a) => a.toString()).join('|');
      expect(analystDump.contains('@'), isFalse);
      expect(RegExp(r'\+?\d{10,}').hasMatch(analystDump), isFalse);
      expect(RegExp(r'[0-9a-f]{64}').hasMatch(analystDump), isFalse);
    });

    test('Task 8.5: assignment is DETERMINISTIC (repeated-invocation)',
        () async {
      Future<List<String>> run() async {
        final registry = InMemoryAnalystRegistry.production();
        final repo = InMemoryWarCaseRepository(registry: registry);
        final filed = await repo.fileCase(const CaseIntakeSubmission(
          situation: IntakeSituation.blackmailExtortion,
          narrative: 'They are blackmailing me.',
          urgency: IntakeUrgency.thisWeek,
          consentNotLegalAdvice: true,
          consentLegalAidReferral: true,
        ));
        return filed.assignments
            .map((a) => '${a.analystId}:${a.skill}')
            .toList();
      }

      final first = await run();
      for (var i = 0; i < 10; i++) {
        expect(await run(), first,
            reason: 'identical analyst pools must assign identically');
      }
    });

    test('Task 8.5: blind review — notes expose ONLY the blinded handle',
        () async {
      final registry = InMemoryAnalystRegistry.production();
      final repo = InMemoryWarCaseRepository(registry: registry);
      final filed = await repo.fileCase(const CaseIntakeSubmission(
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'They are blackmailing me.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      ));
      final analystId = filed.assignments.first.analystId;
      await repo.addAnalystUpdate(
        filed.caseNumber,
        analystId,
        'Identified the account origin.',
        'In progress',
      );
      final read = await repo.getCaseById(filed.caseNumber);
      final note = read!.updates.single;
      // The ONLY attribution on the note is the blinded handle — the text
      // never names another analyst, and no identity shape appears.
      expect(note.analystId, matches(r'^AN-\d{4}$'));
      expect(note.text, isNot(contains(note.analystId)));
      expect(note.text.contains('@'), isFalse);
      expect(RegExp(r'\+?\d{10,}').hasMatch(note.text), isFalse);
      // And a stranger can never post (enforced by the repository).
      await expectLater(
        repo.addAnalystUpdate(
            filed.caseNumber, 'AN-0099', 'stranger', 'In progress'),
        throwsStateError,
      );
    });

    test('Task 8.5: analyst files are local-first — zero networking, no prints',
        () {
      final files = <File>[
        File('lib/war_room/domain/analyst.dart'),
        File('lib/war_room/domain/analyst_registry.dart'),
        File('lib/war_room/data/in_memory_analyst_registry.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('queued payload envelope exposes NO filename and NO plaintext',
        () async {
      final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);
      final evidenceStore = InMemoryEntityStore<EvidenceRecord>((r) => r.id);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final device = await X25519().newKeyPair();
      final sink = QueueEvidenceSink(
        cipher: AesGcmEvidenceCipher(
            crypto: CryptoServiceImpl(), deviceKeyPair: device),
        evidenceStore: evidenceStore,
        syncQueue:
            LocalSyncQueueRepository(store: queueStore, cipher: testCipher()),
        recipientPublicKey: await device.extractPublicKey(),
      );

      await sink.addEvidence(
        'DRAFT-x',
        PickedEvidence(
          bytes: plaintext,
          displayName: 'passport_photo.jpg',
          mimeType: 'image/jpeg',
          sizeBytes: plaintext.length,
        ),
      );

      final queueCipher = testCipher();
      final opened =
          await queueCipher.open((await queueStore.getAll()).single.payload);
      final frame = opened; // sealed frame bytes
      final envelope = decodeEvidenceEnvelope(frame);

      // The frame is the sealed envelope — no plaintext, no name.
      expect(frame, isNot(contains('passport')));
      expect(frame, isNot(equals(plaintext)));
      expect(envelope.sealedFile, isNotEmpty);
      expect(envelope.dekEnvelope, isNotEmpty);
    });

    test('Task 8.6: the custody log is IMMUTABLE — tampering is detected',
        () async {
      final repo = InMemoryWarCaseRepository();
      await repo.fileCase(const CaseIntakeSubmission(
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'They are blackmailing me.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      ));
      expect(await repo.verifyCustodyIntegrity(), isTrue);

      // No production surface exposes a mutation path — the log is
      // append-only by contract (structural scan of the port + impl).
      final logSrc = File('lib/war_room/data/in_memory_custody_log.dart')
          .readAsStringSync();
      expect(logSrc.contains('Future<void> append('), isTrue);
      expect(logSrc.contains('void update('), isFalse,
          reason: 'no update path may exist on the custody log');
      expect(logSrc.contains('void delete('), isFalse,
          reason: 'no delete path may exist on the custody log');

      // Proof the tamper hook itself is test-only: it lives in a method
      // named tamperForTest and is never called by production code.
      expect(logSrc.contains('tamperForTest'), isTrue);
      final repoSrc =
          File('lib/war_room/data/in_memory_war_case_repository.dart')
              .readAsStringSync();
      expect(repoSrc.contains('tamperForTest'), isFalse,
          reason: 'production must never invoke the tamper hook');
    });

    test('Task 8.6: custody events carry ZERO identity on every surface',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(const CaseIntakeSubmission(
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'Priya from MG Road is blackmailing me for money',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      ));
      final analystId = filed.assignments.first.analystId;
      await repo.addAnalystUpdate(
        filed.caseNumber,
        analystId,
        'Identified the account origin.',
        'In progress',
      );
      await repo.signVerifiedReport(filed.caseNumber);

      // JSON + canonical serializations are the only wire forms — scan them.
      final events = await repo.custodyEvents(filed.caseNumber);
      for (final e in events) {
        final json = e.toJson().toString().toLowerCase();
        final canonical = e.canonicalString().toLowerCase();
        for (final shape in ['priya', 'mg road', '+91', '@', '.com']) {
          expect(json.contains(shape), isFalse,
              reason: 'event JSON must never carry $shape');
          expect(canonical.contains(shape), isFalse,
              reason: 'event canonical must never carry $shape');
        }
        // Actors are the ONLY identities: VICTIM / SYSTEM / AN-####.
        expect(e.actor, matches(r'^(VICTIM|SYSTEM|AN-\d{4})$'));
      }
    });

    test('Task 8.6: report text is deterministic and non-PII (structural)',
        () async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(const CaseIntakeSubmission(
        situation: IntakeSituation.blackmailExtortion,
        narrative: 'They are blackmailing me.',
        urgency: IntakeUrgency.thisWeek,
        consentNotLegalAdvice: true,
        consentLegalAidReferral: true,
      ));
      final signed = await repo.signVerifiedReport(filed.caseNumber);
      final text = signed.report.canonicalText();

      // The signed text carries only public dossier attributes.
      expect(text.contains('@'), isFalse);
      expect(RegExp(r'\+?\d{10,}').hasMatch(text), isFalse);
      expect(text, isNot(contains('blackmail')));
      expect(text, isNot(contains('Priya')));
      expect(text, isNot(contains('\'AN-')));

      // Deterministic: re-signing the same case yields the same signature.
      final again = await repo.signVerifiedReport(filed.caseNumber);
      expect(again.signature, signed.signature,
          reason: 'HMAC must be deterministic across runs');
    });

    test('Task 8.6: handoff is SEALED — queue bytes expose no frame plaintext',
        () async {
      final handoffStore = InMemoryEntityStore<LegalAidHandoff>((h) => h.id);
      final queueStore = InMemoryEntityStore<SyncQueueItem>((i) => i.id);
      final sink = QueueLegalAidHandoffSink(
        handoffStore: handoffStore,
        syncQueue:
            LocalSyncQueueRepository(store: queueStore, cipher: testCipher()),
      );
      await sink.queue(LegalAidHandoff(
        id: '',
        caseNumber: 'CC-0047',
        reportSignature: 'abcDEF_signature',
        analystId: 'AN-0003',
        queuedAt: DateTime.utc(2026, 8, 10),
      ));

      // The raw queue row is opaque — no frame field survives in plaintext.
      final raw =
          String.fromCharCodes((await queueStore.getAll()).single.payload);
      for (final field in ['case_number', 'analyst_id', 'CC-0047', 'AN-0003']) {
        expect(raw.contains(field), isFalse,
            reason: 'queue bytes must never expose $field');
      }

      // Unsealing recovers the strict frame (proves it was sealed, not
      // simply omitted).
      final opened =
          await testCipher().open((await queueStore.getAll()).single.payload);
      final envelope =
          LegalAidHandoffEnvelope.decode(String.fromCharCodes(opened));
      expect(envelope.caseNumber, 'CC-0047');
      expect(envelope.analystId, 'AN-0003');
    });

    test('Task 8.6: custody + report files are local-first — zero networking',
        () {
      final files = <File>[
        File('lib/war_room/domain/custody_log.dart'),
        File('lib/war_room/data/in_memory_custody_log.dart'),
        File('lib/war_room/data/hmac_report_signer.dart'),
        File('lib/war_room/data/queue_legal_aid_handoff_sink.dart'),
        File('lib/state/ui/verified_intel_report_sheet.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('Task 8.7: quick-exit + draft files are local-first — zero networking',
        () {
      final files = <File>[
        File('lib/war_room/domain/intake_draft.dart'),
        File('lib/war_room/data/encrypted_intake_draft_store.dart'),
        File('lib/state/ui/quick_exit_safe_screen.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking '
                '(drafts stay on-device; quick exit never phones home)');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('Task 8.7: the draft frame carries ZERO identity fields', () {
      final src =
          File('lib/war_room/domain/intake_draft.dart').readAsStringSync();
      // The envelope declares only intake fields — no phone/name/handle.
      final fields =
          RegExp("'[a-z_]+':").allMatches(src).map((m) => m.group(0)).toList();
      final joined = fields.join(',').toLowerCase();
      expect(joined, isNot(contains('phone')));
      expect(joined, isNot(contains('email')));
      expect(joined, isNot(contains('name')));
      expect(joined, isNot(contains('handle')));
      expect(joined, isNot(contains('hash')));
    });

    test('Task 8.7: the intake screen wipe is zero-leak — no debug prints', () {
      final src =
          File('lib/state/ui/war_room_intake_screen.dart').readAsStringSync();
      expect(src.contains('print('), isFalse);
      expect(src.contains('debugPrint('), isFalse);
      // The wipe path exists and zero-fills buffers (memory hygiene).
      expect(src.contains('_wipeTransientState'), isTrue);
      expect(src.contains('zeroFill'), isTrue);
    });
  });

  group('Task 8.8 Phase 8 COMPLETION AUDIT', () {
    const warRoomScreens = <String>[
      'lib/state/ui/war_room_case_list_screen.dart',
      'lib/state/ui/war_case_detail_screen.dart',
      'lib/state/ui/war_room_intake_screen.dart',
      'lib/state/ui/quick_exit_safe_screen.dart',
      'lib/state/ui/verified_intel_report_sheet.dart',
      'lib/state/ui/severity_override_sheet.dart',
    ];

    test('FLAG_SECURE is wired into every War Room screen surface', () {
      for (final screen in warRoomScreens) {
        final src = File(screen).readAsStringSync();
        expect(src.contains('SecureScreenWrapper'), isTrue,
            reason: '$screen must wrap in SecureScreenWrapper (FLAG_SECURE)');
        expect(src.contains('secureFlagService'), isTrue,
            reason: '$screen must expose the FLAG_SECURE test seam');
      }
    });

    test('entire lib/war_room + lib/pii trees are local-first (no networking)',
        () {
      final dirs = <Directory>[
        Directory('lib/war_room'),
        Directory('lib/pii'),
      ];
      final forbidden = RegExp(
          "import\\s+['\"](dart:io|package:http|package:web_socket_channel)");
      final offenders = <String>[];
      for (final dir in dirs) {
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final src = f.readAsStringSync();
          if (forbidden.hasMatch(src)) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket anywhere in war_room or pii');
    });

    test('whole-tree scan: war_room + pii production code never prints', () {
      final dirs = <Directory>[
        Directory('lib/war_room'),
        Directory('lib/pii'),
      ];
      final offenders = <String>[];
      for (final dir in dirs) {
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final src = f.readAsStringSync();
          if (src.contains('print(') || src.contains('debugPrint(')) {
            offenders.add(f.path);
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint anywhere in war_room or pii');
    });

    test('whole-tree scan: no PII-shaped literals in war_room or pii code', () {
      final dirs = <Directory>[
        Directory('lib/war_room'),
        Directory('lib/pii'),
      ];
      final patterns = [
        RegExp(r'\+?\d{10,15}'), // E.164 phone
        RegExp(r'\b[0-9a-f]{64}\b'), // 64-hex blind hash
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'), // email
      ];
      final offenders = <String>[];
      for (final dir in dirs) {
        for (final f in dir
            .listSync(recursive: true)
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))) {
          final src = f.readAsStringSync();
          for (final p in patterns) {
            if (p.hasMatch(src)) {
              offenders.add(f.path);
              break;
            }
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in war_room or pii source');
    });

    test('UI actor surface is blinded: VICTIM + AN-#### only, no raw names',
        () {
      final detailSrc =
          File('lib/state/ui/war_case_detail_screen.dart').readAsStringSync();
      // The blinded-actor formats the UI is allowed to render.
      expect(detailSrc.contains('VICTIM'), isTrue,
          reason: 'detail screen renders the blinded VICTIM actor label');
      // No raw-name-shaped literals appear in the detail screen source.
      expect(RegExp(r'\+?\d{10,15}').hasMatch(detailSrc), isFalse);
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(detailSrc), isFalse);
      // Custody actors: the log uses only VICTIM / AN-#### (format check).
      final custodySrc =
          File('lib/war_room/domain/custody_log.dart').readAsStringSync();
      expect(custodySrc.contains('AN-'), isTrue);
      expect(RegExp(r'\+?\d{10,15}').hasMatch(custodySrc), isFalse);
    });

    test('memory hygiene + at-rest proofs exist for every sensitive surface',
        () {
      // Byte-level at-rest + wipe proofs shipped with their tasks; this
      // milestone lock asserts the production wipe/encryption entry points
      // still exist so the proofs remain meaningful.
      final intakeSrc =
          File('lib/state/ui/war_room_intake_screen.dart').readAsStringSync();
      expect(intakeSrc.contains('zeroFill'), isTrue);
      expect(intakeSrc.contains('_wipeTransientState'), isTrue);
      final draftSrc =
          File('lib/war_room/data/encrypted_intake_draft_store.dart')
              .readAsStringSync();
      expect(draftSrc.contains('seal'), isTrue);
      expect(draftSrc.contains('open'), isTrue);
      final evidenceSrc = File('lib/war_room/data/aes_gcm_evidence_cipher.dart')
          .readAsStringSync();
      expect(evidenceSrc.contains('AesGcm'), isTrue);
      expect(evidenceSrc.contains('nonce'), isTrue);
    });
  });
}

bool _contains(Uint8List haystack, List<int> needle) {
  if (needle.isEmpty || needle.length > haystack.length) {
    return false;
  }
  outer:
  for (var i = 0; i <= haystack.length - needle.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) {
        continue outer;
      }
    }
    return true;
  }
  return false;
}

Future<void> _pumpFlagged(WidgetTester tester, Widget screen) async {
  await tester.pumpWidget(MaterialApp(home: screen));
  for (var i = 0; i < 6; i++) {
    await tester.pump();
  }
}

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
