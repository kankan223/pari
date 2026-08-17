import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/state/data/local_academy_bloc.dart';
import 'package:civic_commons/state/ui/academy_module_screen.dart';
import 'package:civic_commons/state/ui/academy_syllabus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 9.1 VERIFY: integration test for syllabus navigation — browse the
/// tree, drill into a domain, open a module, mark it complete, and watch
/// the MY PROGRESS projection update through the SAME bloc instance.
void main() {
  testWidgets('syllabus navigation + progress round-trip', (tester) async {
    final store = InMemoryAcademyProgressStore();
    final bloc = LocalAcademyBloc(
      repository: InMemoryAcademySyllabusRepository(),
      store: store,
    );
    addTearDown(bloc.close);
    // start() does real async work — run outside the FakeAsync zone.
    await tester.runAsync(bloc.start);
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: AcademySyllabusScreen(
        bloc: bloc,
        onModuleTap: (moduleId) {
          final module = bloc.current.syllabus!.modules
              .firstWhere((m) => m.moduleId == moduleId);
          final domainTitle = bloc.current.syllabus!.domains
              .firstWhere((d) => d.domainId == module.domainId)
              .title;
          Navigator.of(tester.element(find.byType(AcademySyllabusScreen)))
              .push(MaterialPageRoute<void>(
            builder: (_) => AcademyModuleScreen(
              bloc: bloc,
              module: module,
              domainTitle: domainTitle,
            ),
          ));
        },
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    // Browse by domain → drill into Civic Education. ('Civic Education'
    // appears in BOTH the MY PROGRESS row and the domain card — the card
    // is the tappable one, i.e. the last match.)
    expect(find.text('BROWSE BY DOMAIN'), findsOneWidget);
    await tester.tap(find.text('Civic Education').last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Fundamentals of Civic Rights'), findsOneWidget);

    // Open the module → the module view renders with the breadcrumb.
    await tester.tap(find.text('Fundamentals of Civic Rights'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Civic Education › Fundamentals of Civic Rights'),
        findsOneWidget);
    expect(find.text('VIDEO ROOM'), findsOneWidget);

    // Mark complete → toggle flips.
    await tester.tap(find.byType(Switch));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Module completed'), findsOneWidget);

    // Back to the syllabus → MY PROGRESS reflects the completion. The
    // module screen uses a custom back IconButton ('Back to syllabus'),
    // so tap it directly instead of tester.pageBack().
    await tester.tap(find.byTooltip('Back to syllabus'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('MY PROGRESS'), findsOneWidget);
    expect(find.textContaining('33%'), findsWidgets);

    // The store persisted the toggle (survives bloc restart).
    expect(await store.loadCompletedModuleIds(), isNotEmpty);
  });
}
