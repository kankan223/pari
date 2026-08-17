import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/data/in_memory_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/ui/academy_sandbox_edit_screen.dart';
import 'package:civic_commons/state/ui/academy_sandbox_page_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  final module =
      InMemoryAcademySyllabusRepository.seedSyllabus.modulesFor('civics').first;

  /// Seeds a page with TWO revisions (so the history shows a diff + a
  /// REVERT target) and opens it in the bloc.
  Future<(LocalSandboxWikiBloc, SandboxPage)> readyOpenBloc(
      WidgetTester tester) async {
    final repository = InMemorySandboxWikiRepository();
    final handle = SandboxAuthorHandle.forModule(_m1);
    final page = await repository.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Civic Rights Notes',
        bodyMarkdown: '# One\n\nfirst body',
        locale: 'en',
        authorHandle: handle);
    await repository.submitRevision(
        pageId: page.pageId,
        moduleId: _m1,
        title: 'Civic Rights Notes',
        bodyMarkdown: '# One\n\nrevised body',
        locale: 'en',
        authorHandle: handle);
    final bloc = LocalSandboxWikiBloc(repository: repository);
    await tester.runAsync(() => bloc.start(_m1));
    await tester.runAsync(() => bloc.openPage(page.pageId));
    await tester.pump();
    return (bloc, page);
  }

  testWidgets('renders the page body + revision history with SA handles',
      (tester) async {
    final (bloc, page) = await readyOpenBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxPageScreen(
        bloc: bloc,
        module: module,
        page: page,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Civic Rights Notes'), findsWidgets);
    // The CURRENT body is the latest revision.
    expect(find.textContaining('revised body'), findsOneWidget);
    expect(find.text('REVISION HISTORY'), findsOneWidget);
    // Two revision cards — SA-#### handles, diff counts, CURRENT marker.
    expect(find.textContaining('SA-'), findsNWidgets(2));
    expect(find.textContaining('diff +1 −1'), findsOneWidget);
    expect(find.text('CURRENT'), findsOneWidget);
    expect(find.text('first revision'), findsOneWidget);
  });

  testWidgets('REVERT on an older revision appends a revision', (tester) async {
    final (bloc, page) = await readyOpenBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxPageScreen(
        bloc: bloc,
        module: module,
        page: page,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('REVERT'));
    await tester.pump(const Duration(milliseconds: 300));

    // The reverted (first) body is now current and the history grew.
    expect(find.textContaining('first body'), findsOneWidget);
    expect(bloc.current.revisions, hasLength(3));
  });

  testWidgets('EDIT opens the Markdown editor', (tester) async {
    final (bloc, page) = await readyOpenBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxPageScreen(
        bloc: bloc,
        module: module,
        page: page,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('EDIT'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(AcademySandboxEditScreen), findsOneWidget);
  });

  testWidgets('SECURITY: FLAG_SECURE-wrapped, zero PII, SA handles only',
      (tester) async {
    final (bloc, page) = await readyOpenBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxPageScreen(
        bloc: bloc,
        module: module,
        page: page,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SecureScreenWrapper), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('+91'), findsNothing);
    // No full UUID, no 64-hex hash rendered anywhere.
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'[0-9a-f]{32}').hasMatch(w.data ?? '')),
      findsNothing,
    );
  });
}
