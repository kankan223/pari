import 'package:civic_commons/academy/data/in_memory_academy_syllabus_repository.dart';
import 'package:civic_commons/academy/data/in_memory_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/domain/academy_module.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/security/ui/secure_screen_wrapper.dart';
import 'package:civic_commons/state/data/local_sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/domain/sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/ui/academy_sandbox_edit_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  final module =
      InMemoryAcademySyllabusRepository.seedSyllabus.modulesFor('civics').first;

  Future<LocalSandboxWikiBloc> readyBloc(WidgetTester tester,
      {String? seedTitle}) async {
    final repository = InMemorySandboxWikiRepository();
    if (seedTitle != null) {
      await repository.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: seedTitle,
          bodyMarkdown: '# Existing body',
          locale: 'en',
          authorHandle: SandboxAuthorHandle.forModule(_m1));
    }
    final bloc = LocalSandboxWikiBloc(repository: repository);
    await tester.runAsync(() => bloc.start(_m1));
    await tester.pump();
    return bloc;
  }

  testWidgets('new-page editor shows the SA handle + empty draft',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('NEW SANDBOX PAGE'), findsOneWidget);
    expect(
        find.textContaining('Editing as ${SandboxAuthorHandle.forModule(_m1)}'),
        findsOneWidget);
    expect(find.text('SAVE REVISION'), findsOneWidget);
  });

  testWidgets('existing-page editor pre-fills the latest body', (tester) async {
    final bloc = await readyBloc(tester, seedTitle: 'Civic Rights Notes');
    addTearDown(bloc.close);
    final page = bloc.current.pages.single;

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module, page: page),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('EDIT SANDBOX PAGE'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(TextField).last,
        matching: find.text('# Existing body'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('syntax chips insert Markdown around the selection',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).last, 'bold text');
    // Select the whole body so the chip wraps the selection (a collapsed
    // cursor legitimately inserts the open+close tags adjacent).
    final field = tester.widget<TextField>(find.byType(TextField).last);
    field.controller!.selection =
        const TextSelection(baseOffset: 0, extentOffset: 9);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('BOLD'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(field.controller!.text, '**bold text**');
  });

  testWidgets('PREVIEW toggles the read-only Markdown view', (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.enterText(find.byType(TextField).last, '# Heading');
    await tester.tap(find.text('PREVIEW'));
    await tester.pump(const Duration(milliseconds: 100));

    // The preview renders the raw Markdown read-only.
    expect(find.textContaining('# Heading'), findsOneWidget);
    await tester.tap(find.text('WRITE'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(TextField), findsNWidgets(2));
  });

  testWidgets('SAVE with an empty title is blocked by a snackbar',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    await tester.tap(find.text('SAVE REVISION'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Enter a page title to save.'), findsOneWidget);
    expect(bloc.current.pages, isEmpty);
  });

  testWidgets('SAVE creates the page, consumes the draft and pops',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    // Push the editor from a host route so the post-save pop is observable.
    await tester.pumpWidget(MaterialApp(
      home: _Host(bloc: bloc, module: module),
    ));
    await tester.tap(find.text('OPEN EDITOR'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(AcademySandboxEditScreen), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'Fresh Notes');
    await tester.enterText(find.byType(TextField).last, '# Fresh body');
    await tester.tap(find.text('SAVE REVISION'));
    await tester.pumpAndSettle();

    // The bloc persisted the new page; the draft is consumed.
    expect(bloc.current.pages, hasLength(1));
    expect(bloc.current.pages.single.title, 'Fresh Notes');
    expect(bloc.current.draftBody, isEmpty);
    // The editor popped back to the host.
    expect(find.byType(AcademySandboxEditScreen), findsNothing);
    expect(find.text('OPEN EDITOR'), findsOneWidget);
  });

  testWidgets('SECURITY: FLAG_SECURE-wrapped, only SA-#### + no PII',
      (tester) async {
    final bloc = await readyBloc(tester);
    addTearDown(bloc.close);

    await tester.pumpWidget(MaterialApp(
      home: AcademySandboxEditScreen(bloc: bloc, module: module),
    ));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SecureScreenWrapper), findsOneWidget);
    expect(find.textContaining('@'), findsNothing);
    expect(find.textContaining('+91'), findsNothing);
    expect(
      find.byWidgetPredicate(
          (w) => w is Text && RegExp(r'[0-9a-f]{32}').hasMatch(w.data ?? '')),
      findsNothing,
    );
  });
}

/// Host route that pushes the editor — lets the post-save pop be observed.
class _Host extends StatelessWidget {
  final SandboxWikiBloc bloc;
  final AcademyModule module;

  const _Host({required this.bloc, required this.module});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  AcademySandboxEditScreen(bloc: bloc, module: module),
            ),
          ),
          child: const Text('OPEN EDITOR'),
        ),
      ),
    );
  }
}
