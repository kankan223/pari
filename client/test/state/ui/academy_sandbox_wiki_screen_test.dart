import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/data/in_memory_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/ui/academy_sandbox_page_screen.dart';
import 'package:civic_commons/state/ui/academy_sandbox_wiki_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  final module =
      InMemoryAcademySyllabusRepository.seedSyllabus.modulesFor('civics').first;

  Future<LocalSandboxWikiBloc> readyBloc(WidgetTester tester) async {
    final repository = InMemorySandboxWikiRepository();
    final handle = SandboxAuthorHandle.forModule(_m1);
    await repository.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Civic Rights Notes',
        bodyMarkdown: '# One\n\nfirst',
        locale: 'en',
        authorHandle: handle);
    await repository.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Reporting Basics',
        bodyMarkdown: '# Two',
        locale: 'en',
        authorHandle: handle);
    final bloc = LocalSandboxWikiBloc(repository: repository);
    await tester.runAsync(() => bloc.start(_m1));
    await tester.pump();
    return bloc;
  }

  testWidgets('renders the module-scoped wiki, search + page cards',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxWikiScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('❧ THE ACADEMY'), findsOneWidget);
    expect(find.text('SANDBOX'), findsOneWidget);
    expect(find.textContaining('SANDBOX WIKI'), findsOneWidget);
    expect(find.text('Civic Rights Notes'), findsOneWidget);
    expect(find.text('Reporting Basics'), findsOneWidget);
    // The deterministic pseudonymous handle — never identity.
    expect(find.textContaining('by ${SandboxAuthorHandle.forModule(_m1)}'),
        findsOneWidget);
  });

  testWidgets('search filters the page list live', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxWikiScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField), 'civic');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Civic Rights Notes'), findsOneWidget);
    expect(find.text('Reporting Basics'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No pages match the search.'), findsOneWidget);
  });

  testWidgets('tapping a page opens the page detail screen', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxWikiScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('Civic Rights Notes'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(AcademySandboxPageScreen), findsOneWidget);
    // The page body renders from the revision history.
    expect(find.textContaining('# One'), findsOneWidget);
  });

  testWidgets('failure state shows the generic message + retry recovers',
      (tester) async {
    final bloc = LocalSandboxWikiBloc(repository: _ThrowingRepository());
    addTearDown(bloc.close);
    await tester.runAsync(() => bloc.start(_m1));
    await tester.pump();

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxWikiScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Unable to load the sandbox wiki.'), findsOneWidget);
    // Retry against a still-failing store keeps the generic state (no
    // stack traces or reason leakage).
    await tester.tap(find.text('RETRY'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Unable to load the sandbox wiki.'), findsOneWidget);
  });

  testWidgets('SECURITY: FLAG_SECURE-wrapped, zero PII, no full UUIDs',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxWikiScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SecureScreenWrapper), findsOneWidget);
    // The ONLY handle shape is SA-#### (never a raw identity/email/phone).
    expect(find.textContaining('SA-'), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('+91'), findsNothing);
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'[0-9a-f]{32}').hasMatch(w.data ?? '')),
      findsNothing,
    );
  });
}

class _ThrowingRepository implements SandboxWikiRepository {
  @override
  Future<List<SandboxPage>> listPages({String? moduleId}) =>
      Future.error(StateError('store down'));

  @override
  Future<SandboxPage?> getPage(String pageId) =>
      Future.error(StateError('store down'));

  @override
  Future<List<SandboxRevision>> listRevisions(String pageId) =>
      Future.error(StateError('store down'));

  @override
  Future<SandboxPage> submitRevision({
    required String? pageId,
    required String moduleId,
    required String title,
    required String bodyMarkdown,
    required String locale,
    required String authorHandle,
  }) =>
      Future.error(StateError('store down'));

  @override
  Future<SandboxPage> revertToRevision({
    required String pageId,
    required String revisionId,
    required String authorHandle,
  }) =>
      Future.error(StateError('store down'));
}
