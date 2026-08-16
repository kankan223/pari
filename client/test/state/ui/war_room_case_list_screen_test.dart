import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_war_room_bloc.dart';
import 'package:civic_commons/state/ui/war_room_case_list_screen.dart';
import 'package:civic_commons/state/ui/war_room_theme.dart';
import 'package:civic_commons/war_room/data/in_memory_war_case_repository.dart';
import 'package:civic_commons/war_room/domain/case_severity.dart';
import 'package:civic_commons/war_room/domain/case_status.dart';
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

  WarRoomCase makeCase(String stamp,
          {String title = 'Digital extortion — photo leak threat',
          CaseSeverity severity = CaseSeverity.high,
          CaseStatus status = CaseStatus.underInvestigation,
          bool paused = false}) =>
      WarRoomCase(
        caseNumber: stamp,
        title: title,
        description: 'd',
        severity: severity,
        status: status,
        filedAt: t0,
        paused: paused,
        analystCount: 2,
        estReportHours: 48,
      );

  Future<LocalWarRoomBloc> pump(WidgetTester tester,
      {List<WarRoomCase> seed = const [],
      ValueChanged<String>? onCaseTap,
      VoidCallback? onFileNewCase,
      _RecordingFlagService? flag}) async {
    final repo = InMemoryWarCaseRepository(seed: seed);
    final bloc = LocalWarRoomBloc(repository: repo);
    await tester.pumpWidget(MaterialApp(
      home: WarRoomCaseListScreen(
        bloc: bloc,
        onCaseTap: onCaseTap,
        onFileNewCase: onFileNewCase,
        secureFlagService: flag,
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump();
    }
    return bloc;
  }

  group('WarRoomCaseListScreen (Task 8.1)', () {
    testWidgets('renders masthead + case cards with severity bands',
        (tester) async {
      final flag = _RecordingFlagService();
      final bloc = await pump(tester,
          seed: [
            makeCase('CC-0047'),
            makeCase('CC-0031',
                title: 'Fake social media profile — identity theft',
                severity: CaseSeverity.medium,
                status: CaseStatus.reportReady),
          ],
          flag: flag);

      expect(find.text('▌WAR ROOM▐'), findsOneWidget);
      expect(find.text('CASE #CC-0047'), findsOneWidget);
      expect(
          find.text('Digital extortion — photo leak threat'), findsOneWidget);
      expect(find.text('CASE #CC-0031'), findsOneWidget);
      expect(find.text('Fake social media profile — identity theft'),
          findsOneWidget);
      expect(find.text('HIGH SEVERITY'), findsOneWidget);
      expect(find.text('MEDIUM SEVERITY'), findsOneWidget);
      expect(find.textContaining('UNDER INVESTIGATION'), findsOneWidget);
      expect(find.textContaining('REPORT READY'), findsOneWidget);
      expect(find.text('2 analysts assigned · Est. report: 48 hrs'),
          findsNWidgets(2));

      await bloc.close();
    });

    testWidgets('FLAG_SECURE is enabled on the case list screen',
        (tester) async {
      final flag = _RecordingFlagService();
      final bloc = await pump(tester, seed: [makeCase('CC-0047')], flag: flag);
      expect(flag.enableCalls, greaterThanOrEqualTo(1));
      await bloc.close();
    });

    testWidgets('card tap opens the case; FAB opens intake', (tester) async {
      String? opened;
      var filing = false;
      final bloc = await pump(tester,
          seed: [makeCase('CC-0047')],
          onCaseTap: (id) => opened = id,
          onFileNewCase: () => filing = true);

      await tester.tap(find.text('Digital extortion — photo leak threat'));
      expect(opened, 'CC-0047');

      await tester.tap(find.byType(FloatingActionButton));
      expect(filing, isTrue);
      await bloc.close();
    });

    testWidgets('empty state prompts first-time victims', (tester) async {
      final bloc = await pump(tester);
      expect(find.text('No cases yet'), findsOneWidget);
      expect(find.text('File a new case'), findsWidgets);
      await bloc.close();
    });

    testWidgets('paused and withdrawn cases render status tags',
        (tester) async {
      final bloc = await pump(tester, seed: [
        makeCase('CC-0001', paused: true),
        makeCase('CC-0002', status: CaseStatus.withdrawn),
      ]);
      expect(find.text('PAUSED'), findsOneWidget);
      expect(find.text('WITHDRAWN'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('list background uses the manila paper surface',
        (tester) async {
      final bloc = await pump(tester, seed: [makeCase('CC-0047')]);
      final scaffold = tester.widget<Scaffold>(find.byType(Scaffold));
      expect(scaffold.backgroundColor, WarRoomTheme.manilaPaper);
      await bloc.close();
    });
  });
}
