import 'package:civic_commons/academy/data/in_memory_academy_progress_store.dart';
import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart' as domain;
import 'package:civic_commons/academy/domain/academy_syllabus_repository.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_academy_bloc.dart';
import 'package:civic_commons/state/ui/academy_syllabus_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a ready [LocalAcademyBloc] over the deterministic seed syllabus.
///
/// The bloc's [LocalAcademyBloc.start] performs REAL async work
/// (repository/store futures), which cannot complete under the widget
/// test's FakeAsync zone — run it inside [WidgetTester.runAsync].
Future<LocalAcademyBloc> _readyBloc(
  WidgetTester tester, {
  Set<String>? completed,
}) async {
  final store = InMemoryAcademyProgressStore();
  for (final id in completed ?? const <String>{}) {
    await store.markModuleComplete(id);
  }
  final bloc = LocalAcademyBloc(
    repository: InMemoryAcademySyllabusRepository(),
    store: store,
  );
  await tester.runAsync(bloc.start);
  await tester.pump();
  return bloc;
}

void main() {
  final seed = InMemoryAcademySyllabusRepository.seedSyllabus;
  final civicsModule = seed.modulesFor('civics').first;

  testWidgets('renders masthead, MY PROGRESS and BROWSE BY DOMAIN',
      (tester) async {
    final bloc = await _readyBloc(tester);
    addTearDown(bloc.close);

    await tester
        .pumpWidget(MaterialApp(home: AcademySyllabusScreen(bloc: bloc)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('❧ THE ACADEMY'), findsOneWidget);
    expect(find.text('MY PROGRESS'), findsOneWidget);
    expect(find.text('BROWSE BY DOMAIN'), findsOneWidget);
    // Seed domains + their module counts.
    expect(find.text('Civic Education'), findsWidgets);
    expect(find.text('Technology'), findsWidgets);
  });

  testWidgets('progress tracking UI shows completion percentages',
      (tester) async {
    final bloc = await _readyBloc(tester,
        completed: {civicsModule.moduleId}); // 1 of 3 → 33%
    addTearDown(bloc.close);

    await tester
        .pumpWidget(MaterialApp(home: AcademySyllabusScreen(bloc: bloc)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('33%'), findsWidgets);
    // One civics module done → 1/2 civics, 0/1 tech.
    expect(find.textContaining('1/2'), findsOneWidget);
    expect(find.textContaining('0/1'), findsOneWidget);
  });

  testWidgets('tapping a domain opens its module list, back returns',
      (tester) async {
    final bloc = await _readyBloc(tester);
    addTearDown(bloc.close);

    await tester
        .pumpWidget(MaterialApp(home: AcademySyllabusScreen(bloc: bloc)));
    await tester.pump(const Duration(
        milliseconds:
            100)); // 'Civic Education' appears in BOTH the MY PROGRESS row and the domain
    // card — target the card (last match), which is the tappable one.
    await tester.tap(find.text('Civic Education').last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));

    // The civics module rows render (module title + meta).
    expect(find.text('Fundamentals of Civic Rights'), findsOneWidget);
    expect(find.text('18 min · en'), findsOneWidget);
    expect(find.text('All domains'), findsOneWidget);

    await tester.tap(find.text('All domains'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('BROWSE BY DOMAIN'), findsOneWidget);
  });

  testWidgets('module tap fires onModuleTap with the module id',
      (tester) async {
    final bloc = await _readyBloc(tester);
    addTearDown(bloc.close);
    String? tapped;

    await tester.pumpWidget(MaterialApp(
      home: AcademySyllabusScreen(
        bloc: bloc,
        onModuleTap: (id) => tapped = id,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Civic Education').last, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text('Fundamentals of Civic Rights'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(tapped, civicsModule.moduleId);
  });

  testWidgets('failure state shows generic message + retry recovers',
      (tester) async {
    var failures = 1;
    final bloc = LocalAcademyBloc(
      repository: _FlakyRepository(failures: () => failures),
      store: InMemoryAcademyProgressStore(),
    );
    addTearDown(bloc.close);
    await tester.runAsync(bloc.start);
    await tester.pump();

    await tester
        .pumpWidget(MaterialApp(home: AcademySyllabusScreen(bloc: bloc)));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Unable to load the syllabus.'), findsOneWidget);

    failures = 0; // recovered
    await tester.tap(find.text('Retry'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('BROWSE BY DOMAIN'), findsOneWidget);
  });

  testWidgets('SECURITY: screen is FLAG_SECURE-wrapped and zero-PII',
      (tester) async {
    final bloc = await _readyBloc(tester);
    addTearDown(bloc.close);

    await tester
        .pumpWidget(MaterialApp(home: AcademySyllabusScreen(bloc: bloc)));
    await tester.pump(const Duration(milliseconds: 100));

    // The masthead's SecureScreenWrapper is in the tree (FLAG_SECURE).
    expect(find.byType(SecureScreenWrapper), findsOneWidget);

    // No PII-shaped text anywhere in the rendered tree.
    expect(find.textContaining('+91'), findsNothing);
    expect(find.textContaining('@'), findsNothing);
    expect(
        find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'[0-9a-f]{64}').hasMatch(w.data ?? ''),
        ),
        findsNothing);
  });
}

/// Repository that fails until the scripted flag flips.
class _FlakyRepository implements AcademySyllabusRepository {
  final int Function() failures;

  _FlakyRepository({required this.failures});

  @override
  Future<domain.AcademySyllabus> fetchSyllabus() async {
    if (failures() > 0) {
      throw StateError('syllabus unavailable');
    }
    return InMemoryAcademySyllabusRepository.seedSyllabus;
  }
}
