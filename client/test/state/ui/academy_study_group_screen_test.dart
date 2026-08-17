import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/data/in_memory_study_group_repository.dart';
import 'package:civic_commons/academy/domain/study_group.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_study_group_bloc.dart';
import 'package:civic_commons/state/ui/academy_study_group_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSecureFlagService implements SecureFlagService {
  bool enabled = false;

  @override
  Future<void> enableSecureFlag() async => enabled = true;

  @override
  Future<void> disableSecureFlag() async => enabled = false;

  @override
  Future<bool> isSecureFlagSupported() async => true;
}

void main() {
  final module =
      InMemoryAcademySyllabusRepository.seedSyllabus.modulesFor('civics').first;

  Future<LocalStudyGroupBloc> readyBloc(WidgetTester tester,
      {InMemoryStudyGroupRepository? repo}) async {
    final repository = repo ?? InMemoryStudyGroupRepository();
    await repository.seedGroup(
      moduleId: module.moduleId,
      title: 'Civic Rights Study Circle',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(
            pillar: StudyPillar.academy, topicId: module.moduleId),
        StudyTopicRef.parse(pillar: StudyPillar.ledger, topicId: 'civics'),
      ],
      capacity: 6,
    );
    final bloc = LocalStudyGroupBloc(repository: repository);
    await tester.runAsync(() =>
        bloc.start(moduleId: module.moduleId, pinCode: '800001', locale: 'en'));
    await tester.pump();
    return bloc;
  }

  testWidgets('renders the blinded handle, scope and match cards',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyStudyGroupScreen(
        bloc: bloc,
        module: module,
        pinCode: '800001',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Blinded SG-#### handle — never an identity.
    final handle = StudyGroupHandle.forModule(module.moduleId);
    expect(find.text('You study as $handle · scope 800001'), findsOneWidget);
    expect(find.textContaining('MATCHES — best fit for your scope'),
        findsOneWidget);
    expect(find.text('SCORE 11'),
        findsOneWidget); // 5 anchor + 2 locale + 4 pin (deterministic).
    expect(find.text('Civic Rights Study Circle'), findsWidgets);
    // Zero PII: the full 64-hex blind hash / phone shapes never render.
    expect(find.textContaining(module.moduleId), findsNothing);
  });

  testWidgets('FLAG_SECURE is active on mount', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);
    final flag = FakeSecureFlagService();

    await tester.pumpWidget(MaterialApp(
      home: AcademyStudyGroupScreen(
        bloc: bloc,
        module: module,
        pinCode: '800001',
        secureFlagService: flag,
      ),
    ));
    await tester.pump();

    expect(flag.enabled, isTrue, reason: 'FLAG_SECURE must be active');
  });

  testWidgets('join flow updates the UI through the bloc', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyStudyGroupScreen(
        bloc: bloc,
        module: module,
        pinCode: '800001',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Tap to join'), findsWidgets);
    final joinButton = find.text('JOIN GROUP');
    await tester.tap(joinButton.first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('You are in this group'), findsWidgets);
    expect(find.text('✓ Joined'), findsOneWidget);
  });

  testWidgets('search filters groups by title', (tester) async {
    final repo = InMemoryStudyGroupRepository();
    await repo.seedGroup(
      moduleId: module.moduleId,
      title: 'Civic Rights Circle',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(
            pillar: StudyPillar.academy, topicId: module.moduleId),
      ],
      capacity: 5,
    );
    await repo.seedGroup(
      moduleId: module.moduleId,
      title: 'Constitution Jam',
      locale: 'en',
      pinCode: '800001',
      topics: [
        StudyTopicRef.parse(
            pillar: StudyPillar.academy, topicId: module.moduleId),
      ],
      capacity: 5,
    );
    final bloc = await readyBloc(tester, repo: repo);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyStudyGroupScreen(
        bloc: bloc,
        module: module,
        pinCode: '800001',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).first, 'constitution');
    await tester.pump();

    // The MATCHES section is unfiltered (deterministic best-fit), so the
    // search assertion targets the group LIST below it: only the matching
    // title survives the filter (each list card carries a 'Tap to join'
    // marker; the match cards carry JOIN GROUP buttons instead).
    expect(find.text('Constitution Jam'), findsWidgets);
    final joinMarkers = find.text('Tap to join');
    expect(joinMarkers, findsOneWidget);
    final listCard = find
        .ancestor(
          of: joinMarkers,
          matching: find.byType(InkWell),
        )
        .first;
    expect(
      find.descendant(of: listCard, matching: find.text('Civic Rights Circle')),
      findsNothing,
    );
    expect(
      find.descendant(of: listCard, matching: find.text('Constitution Jam')),
      findsOneWidget,
    );
  });

  testWidgets('create-group sheet creates a group through the bloc',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademyStudyGroupScreen(
        bloc: bloc,
        module: module,
        pinCode: '800001',
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Open the create sheet from the app-bar NEW action (always reachable,
    // even when groups already exist).
    await tester.tap(find.text('NEW'));
    await tester.pumpAndSettle();

    await tester.enterText(
        find.widgetWithText(TextField, 'Group title (public)'), 'New Circle');
    await tester.pump();
    await tester.tap(find.text('CREATE'));
    await tester.pumpAndSettle();

    // Back on the browse screen, the new group is visible in the list.
    expect(find.text('New Circle'), findsWidgets);
  });
}
