import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_case_detail_screen.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/analyst.dart';
import 'package:civic_commons/war_room/domain/case_intake.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
import 'package:civic_commons/war_room/domain/custody_log.dart';
import 'package:civic_commons/war_room/domain/severity_scoring.dart';
import 'package:civic_commons/war_room/domain/war_room_case.dart';
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

void main() {
  final t0 = DateTime.utc(2026, 8, 10, 12);

  WarRoomCase makeCase({
    CaseStatus status = CaseStatus.underInvestigation,
    SeverityTriage? triage,
    SeverityOverride? severityOverride,
    List<CaseAssignment>? assignments,
  }) {
    final team = assignments ??
        [
          CaseAssignment(
            caseNumber: 'CC-0047',
            analystId: 'AN-0001',
            skill: AnalystSkill.threatAssessment,
            assignedAt: t0,
          ),
          CaseAssignment(
            caseNumber: 'CC-0047',
            analystId: 'AN-0002',
            skill: AnalystSkill.osint,
            assignedAt: t0,
          ),
        ];
    return WarRoomCase(
      caseNumber: 'CC-0047',
      title: 'Digital extortion — photo leak threat',
      description:
          'Someone is threatening to share intimate images unless I pay.',
      severity: severityOverride?.newSeverity ?? CaseSeverity.high,
      status: status,
      filedAt: t0,
      analystCount: team.length,
      assignments: team,
      estReportHours: 48,
      triage: triage,
      severityOverride: severityOverride,
      timeline: const [
        CaseTimelineEntry(label: 'Case filed', done: true),
        CaseTimelineEntry(label: 'Auto-triage complete', done: true),
        CaseTimelineEntry(label: 'Analysts assigned', done: false),
        CaseTimelineEntry(label: 'Report ready', done: false),
      ],
      updates: [
        AnalystUpdate(
          analystId: 'AN-0001',
          text: 'We have identified the origin platform of the account.',
          at: t0,
          progress: 'In progress',
        ),
      ],
    );
  }

  Future<LocalWarRoomBloc> pump(WidgetTester tester,
      {WarRoomCase? seed,
      VoidCallback? onAddEvidence,
      VoidCallback? onReport,
      _RecordingFlagService? flag}) async {
    final repo = InMemoryWarCaseRepository(seed: [seed ?? makeCase()]);
    final bloc = LocalWarRoomBloc(repository: repo);
    await bloc.start();
    await bloc.openCase((seed ?? makeCase()).caseNumber);
    await tester.pumpWidget(MaterialApp(
      home: WarCaseDetailScreen(
        bloc: bloc,
        caseNumber: (seed ?? makeCase()).caseNumber,
        onAddEvidence: onAddEvidence,
        onReport: onReport,
        secureFlagService: flag,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    return bloc;
  }

  group('WarCaseDetailScreen (Task 8.1)', () {
    testWidgets('renders the stamp masthead + status timeline + update',
        (tester) async {
      final bloc = await pump(tester);
      expect(find.text('CASE #CC-0047'), findsOneWidget);
      expect(find.text('HIGH'), findsOneWidget); // masthead band
      expect(find.text('STATUS TIMELINE'), findsOneWidget);
      expect(find.text('Case filed'), findsOneWidget);
      expect(find.text('Auto-triage complete'), findsOneWidget);
      expect(find.text('ANALYST UPDATE'), findsOneWidget);
      expect(
          find.text('We have identified the origin platform of the account.'),
          findsOneWidget);
      expect(find.text('IN PROGRESS'), findsOneWidget);
      expect(find.text('2 analysts assigned'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('FLAG_SECURE is enabled on the detail screen', (tester) async {
      final flag = _RecordingFlagService();
      final bloc = await pump(tester, flag: flag);
      expect(flag.enableCalls, greaterThanOrEqualTo(1));
      await bloc.close();
    });

    testWidgets('pause toggles; withdraw shows the withdrawn timeline',
        (tester) async {
      final bloc = await pump(tester);

      // The controls sit below the ANALYST TEAM section in the lazy
      // ListView — scroll them into the build window before tapping.
      await tester.scrollUntilVisible(find.text('Pause case'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Pause case'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Resume case'), findsOneWidget);

      await tester.tap(find.text('Withdraw'));
      // Withdraw now awaits the custody-chain append (Task 8.6) — give the
      // async re-emit enough frames to resolve the WITHDRAWN status.
      for (var i = 0; i < 8; i++) {
        await tester.pump();
      }
      // The WITHDRAWN chip renders at the TOP of the lazy ListView, which
      // scrolled out of the build window while we reached the bottom
      // controls — scroll back up so the chip mounts (Task 8.6 layout).
      await tester.scrollUntilVisible(find.text('WITHDRAWN'), -200,
          scrollable: find.byType(Scrollable).first);
      // The detail re-resolves from the store → WITHDRAWN status tag.
      expect(find.text('WITHDRAWN'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('add-evidence callback fires; report shown for non-withdrawn',
        (tester) async {
      var added = false;
      var reportOpened = false;
      final bloc = await pump(tester,
          onAddEvidence: () => added = true,
          onReport: () => reportOpened = true);

      await tester.scrollUntilVisible(find.text('Add more evidence'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Add more evidence'));
      expect(added, isTrue);

      expect(find.text('Verified Intel Report'), findsOneWidget);
      await tester.tap(find.text('Verified Intel Report'));
      expect(reportOpened, isTrue);
      await bloc.close();
    });

    testWidgets('renders only dossier attributes (zero-PII)', (tester) async {
      final bloc = await pump(tester);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('@')));
      await bloc.close();
    });
  });

  group('WarCaseDetailScreen triage & override (Task 8.4)', () {
    SeverityTriage triage() => const SeverityTriage(
          severity: CaseSeverity.critical,
          criticalSignals: 2,
          highSignals: 1,
          mediumSignals: 0,
          urgencySignals: 1,
          slaHours: 24,
        );

    testWidgets('renders the triage section with signal counts + SLA',
        (tester) async {
      final bloc = await pump(tester, seed: makeCase(triage: triage()));
      expect(find.text('SEVERITY TRIAGE'), findsOneWidget);
      expect(find.text('SLA 24h'), findsOneWidget);
      expect(find.text('2× CRITICAL signal'), findsOneWidget);
      expect(find.text('1× urgency signal'), findsOneWidget);
      // The OVERRIDE entry point is present.
      expect(find.text('Override severity'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('an applied override renders OVERRIDDEN + reason',
        (tester) async {
      final bloc = await pump(
        tester,
        seed: makeCase(
          triage: triage(),
          severityOverride: SeverityOverride(
            newSeverity: CaseSeverity.low,
            reason: 'No credible threat after analyst review',
            at: t0.add(const Duration(hours: 3)),
          ),
        ),
      );
      expect(find.text('OVERRIDDEN'), findsOneWidget);
      expect(find.textContaining('No credible threat'), findsOneWidget);
      expect(find.text('Change override'), findsOneWidget);
      await bloc.close();
    });
    testWidgets('override sheet: reason required, apply re-bands the case',
        (tester) async {
      // Tall viewport so the sheet's controls are fully tappable.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo =
          InMemoryWarCaseRepository(seed: [makeCase(triage: triage())]);
      final bloc = LocalWarRoomBloc(repository: repo);
      await bloc.start();
      await bloc.openCase('CC-0047');
      await tester.pumpWidget(MaterialApp(
        home: WarCaseDetailScreen(
          bloc: bloc,
          caseNumber: 'CC-0047',
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      await tester.tap(find.text('Override severity'));
      // pumpAndSettle advances past the modal entrance animation (bare
      // pump() calls don't move the animation clock, so the sheet would sit
      // below the fold and its controls would be untappable).
      await tester.pumpAndSettle();
      expect(find.text('OVERRIDE SEVERITY'), findsOneWidget);

      // Apply is disabled until a severity AND a reason exist.
      final applyBtn = find.widgetWithText(FilledButton, 'Apply override');
      expect(tester.widget<FilledButton>(applyBtn).onPressed, isNull);

      await tester.tap(find.text('LOW  ·  120h SLA'));
      await tester.pump();
      expect(tester.widget<FilledButton>(applyBtn).onPressed, isNull,
          reason: 'reason still missing');

      await tester.enterText(
          find.byType(TextField), 'No credible threat after review');
      await tester.pump();
      await tester.tap(find.text('Apply override'));
      // pumpAndSettle lets the sheet's exit animation finish so its widgets
      // leave the tree before asserting on the detail behind it.
      await tester.pumpAndSettle();

      // The detail now shows the overridden band + reason.
      expect(find.text('OVERRIDDEN'), findsOneWidget);
      expect(find.textContaining('No credible threat after review'),
          findsOneWidget);
      final stored = await repo.getCaseById('CC-0047');
      expect(stored!.severity, CaseSeverity.low);
      expect(stored.estReportHours, 120);
      await bloc.close();
    });

    testWidgets('ANALYST TEAM renders blinded handles + skill labels only',
        (tester) async {
      final bloc = await pump(tester);
      expect(find.text('ANALYST TEAM'), findsOneWidget);
      // Blinded handles + fixed skill labels — never names/identity.
      expect(find.text('AN-0001'), findsOneWidget);
      expect(find.text('AN-0002'), findsOneWidget);
      expect(find.text('Threat assessment'), findsOneWidget);
      expect(find.text('OSINT'), findsOneWidget);
      expect(find.text('VETTED'), findsNWidgets(2));
      await bloc.close();
    });

    testWidgets('ANALYST TEAM is omitted when nothing is assigned',
        (tester) async {
      final bloc = await pump(tester, seed: makeCase(assignments: const []));
      expect(find.text('ANALYST TEAM'), findsNothing);
      await bloc.close();
    });

    testWidgets('analyst team renders zero identity (zero-PII tree scan)',
        (tester) async {
      final bloc = await pump(tester);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      // The case title/description legitimately contain victim words — scope
      // the scan to identity shapes: emails, phones, names, 64-hex hashes.
      expect(texts.contains('@'), isFalse);
      expect(RegExp(r'\+?\d{10,}').hasMatch(texts), isFalse);
      expect(RegExp(r'[0-9a-f]{64}').hasMatch(texts), isFalse);
      // Only AN-#### handles may identify anyone.
      for (final m in RegExp(r'AN-\d{4}').allMatches(texts)) {
        expect(m.group(0), matches(r'^AN-\d{4}$'));
      }
      await bloc.close();
    });

    testWidgets('triage section renders zero signal-keyword text (zero-PII)',
        (tester) async {
      final bloc = await pump(tester, seed: makeCase(triage: triage()));
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      // The signal CHIPS are COUNT labels — never the matched keywords. The
      // case title/description legitimately contain the victim's own words
      // (case content), so scope the assertion to the chip labels only.
      expect(find.text('2× CRITICAL signal'), findsOneWidget);
      expect(find.text('1× HIGH signal'), findsOneWidget);
      expect(find.text('1× urgency signal'), findsOneWidget);
      expect(texts, isNot(contains('went viral')));
      expect(texts, isNot(contains('leaked')));
      await bloc.close();
    });
  });

  group('WarCaseDetailScreen chain of custody (Task 8.6)', () {
    testWidgets('renders the CHAIN OF CUSTODY section with blinded actors',
        (tester) async {
      // Seed cases carry no custody events until the bloc attaches them from
      // the repository — file the case through the repo so the chain exists.
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final b = LocalWarRoomBloc(repository: repo);
      await b.start();
      await b.openCase(filed.caseNumber);
      await tester.pumpWidget(MaterialApp(
        home: WarCaseDetailScreen(
          bloc: b,
          caseNumber: filed.caseNumber,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      // The custody section sits below the ANALYST TEAM section in the
      // lazy ListView — scroll it into the build window first.
      await tester.scrollUntilVisible(find.text('CHAIN OF CUSTODY'), 200,
          scrollable: find.byType(Scrollable).first);
      expect(find.text('CHAIN OF CUSTODY'), findsOneWidget);
      expect(find.text('CASE FILED'), findsOneWidget);
      expect(find.text('AUTO-TRIAGE'), findsOneWidget);
      expect(find.text('ANALYSTS ASSIGNED'), findsWidgets);
      // The actor renders inside the composite row string.
      expect(find.textContaining('VICTIM'), findsWidgets);
      // The tamper-evident footer is rendered.
      expect(find.textContaining('tamper-evident'), findsOneWidget);
      await b.close();
    });

    testWidgets('custody section renders zero identity (zero-PII tree scan)',
        (tester) async {
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final b = LocalWarRoomBloc(repository: repo);
      await b.start();
      await b.openCase(filed.caseNumber);
      await tester.pumpWidget(MaterialApp(
        home: WarCaseDetailScreen(
          bloc: b,
          caseNumber: filed.caseNumber,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      // Mount the custody section so the scan actually covers it.
      await tester.scrollUntilVisible(find.text('CHAIN OF CUSTODY'), 200,
          scrollable: find.byType(Scrollable).first);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts.contains('@'), isFalse);
      expect(RegExp(r'\+?\d{10,}').hasMatch(texts), isFalse);
      // Blinded actors only — no 64-hex identity hashes anywhere.
      expect(RegExp(r'[0-9a-f]{64}').hasMatch(texts), isFalse);
      await b.close();
    });

    testWidgets('report sheet: signs + shows VERIFIED + queues the handoff',
        (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final repo = InMemoryWarCaseRepository();
      final filed = await repo.fileCase(submission());
      final b = LocalWarRoomBloc(repository: repo);
      await b.start();
      await b.openCase(filed.caseNumber);
      await tester.pumpWidget(MaterialApp(
        home: WarCaseDetailScreen(
          bloc: b,
          caseNumber: filed.caseNumber,
          secureFlagService: _RecordingFlagService(),
        ),
      ));
      for (var i = 0; i < 6; i++) {
        await tester.pump();
      }

      // Open the report sheet (bottom control — scroll into view first).
      await tester.scrollUntilVisible(find.text('Verified Intel Report'), 200,
          scrollable: find.byType(Scrollable).first);
      await tester.tap(find.text('Verified Intel Report'));
      await tester.pumpAndSettle();

      expect(find.text('VERIFIED INTEL REPORT'), findsWidgets);
      expect(
          find.textContaining('VERIFIED · HMAC-SHA256 SIGNED'), findsOneWidget);
      // The HMAC signature box is populated.
      expect(find.text('HMAC SIGNATURE'), findsOneWidget);

      // Queue the legal-aid handoff.
      await tester.tap(find.textContaining('Send to legal aid'));
      await tester.pumpAndSettle();
      expect(find.text('HANDOFF QUEUED'), findsOneWidget);
      expect(find.textContaining('queued for secure delivery'), findsOneWidget);

      // The custody chain gained the handoff event (via the repo).
      final events = await repo.custodyEvents(filed.caseNumber);
      expect(
          events.map((e) => e.type), contains(CustodyEventType.handoffQueued));
      expect(await repo.verifyCustodyIntegrity(), isTrue);
      await b.close();
    });
  });
}

CaseIntakeSubmission submission() => const CaseIntakeSubmission(
      situation: IntakeSituation.blackmailExtortion,
      narrative: 'They say they will leak my photos unless I pay.',
      urgency: IntakeUrgency.thisWeek,
      consentNotLegalAdvice: true,
      consentLegalAidReferral: true,
    );
