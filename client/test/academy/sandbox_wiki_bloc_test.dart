import 'package:civic_commons/academy/data/in_memory_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/state/data/local_sandbox_wiki_bloc.dart';
import 'package:civic_commons/state/domain/sandbox_wiki_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';

/// Repository whose every operation fails (graceful-degradation test).
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

void main() {
  group('LocalSandboxWikiBloc (Task 9.5)', () {
    test('start() loads the module-scoped pages', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      expect(bloc.current.phase, SandboxWikiPhase.ready);
      expect(bloc.current.moduleId, _m1);
      expect(bloc.current.pages, hasLength(2));
      // The deterministic pseudonymous handle for the scope.
      expect(bloc.current.authorHandle, SandboxAuthorHandle.forModule(_m1));
    });

    test('search() filters pages case-insensitively by title', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      bloc.search('civic');
      expect(bloc.current.filteredPages, hasLength(1));
      expect(bloc.current.filteredPages.single.title, 'Civic Rights Notes');

      bloc.search('zzz');
      expect(bloc.current.filteredPages, isEmpty);

      bloc.search('');
      expect(bloc.current.filteredPages, hasLength(2));
    });

    test('openPage() loads the selected page + its revision history', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);
      final page = bloc.current.pages.first;

      await bloc.openPage(page.pageId);

      expect(bloc.current.selectedPage?.pageId, page.pageId);
      expect(bloc.current.revisions, isNotEmpty);
    });

    test('submitDraft() creates a page, consumes the draft, refreshes',
        () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);
      final before = bloc.current.pages.length;

      bloc.setDraft('# New page body');
      expect(bloc.current.draftBody, '# New page body');

      await bloc.submitDraft(title: 'Fresh Notes');

      expect(bloc.current.pages, hasLength(before + 1));
      expect(bloc.current.draftBody, isEmpty); // consumed by the submit
      expect(bloc.current.selectedPage?.title, 'Fresh Notes');
    });

    test('submitDraft() on an open page appends a revision', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);
      final page = bloc.current.pages.first;
      await bloc.openPage(page.pageId);
      final countBefore = bloc.current.revisions.length;

      bloc.setDraft('revision two');
      await bloc.submitDraft(title: page.title);

      expect(bloc.current.revisions, hasLength(countBefore + 1));
      expect(bloc.current.selectedPage!.revisionCount, countBefore + 1);
    });

    test('revertTo() appends the reverted body and reloads', () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);
      final page = bloc.current.pages.first;
      await bloc.openPage(page.pageId);
      final firstBody = bloc.current.revisions.first.bodyMarkdown;
      final countBefore = bloc.current.revisions.length;

      await bloc.revertTo(bloc.current.revisions.first.revisionId);

      expect(bloc.current.revisions, hasLength(countBefore + 1));
      expect(bloc.current.revisions.last.bodyMarkdown, firstBody);
    });

    test('a store outage degrades to the generic failure state', () async {
      final bloc = LocalSandboxWikiBloc(repository: _ThrowingRepository());
      addTearDown(bloc.close);

      await bloc.start(_m1);

      expect(bloc.current.phase, SandboxWikiPhase.failure);
      expect(bloc.current.errorMessage, isNotEmpty);
      // The generic message never leaks a reason/stack.
      expect(bloc.current.errorMessage, contains('sandbox wiki'));
    });

    test('SECURITY: state carries UUID page ids + public content only',
        () async {
      final bloc = await _readyBloc();
      addTearDown(bloc.close);

      for (final page in bloc.current.pages) {
        expect(
          page.pageId,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')),
        );
      }
      // The ONLY handle shape in state is SA-####.
      expect(bloc.current.authorHandle, matches(RegExp(r'^SA-[0-9a-f]{4}$')));
      expect(bloc.current.authorHandle, isNot(contains('@')));
    });
  });
}

Future<LocalSandboxWikiBloc> _readyBloc() async {
  final repository = InMemorySandboxWikiRepository();
  // Seed two pages for _m1 and one for _m2.
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
  await repository.submitRevision(
      pageId: null,
      moduleId: _m2,
      title: 'Other Module',
      bodyMarkdown: '# Three',
      locale: 'en',
      authorHandle: SandboxAuthorHandle.forModule(_m2));
  final bloc = LocalSandboxWikiBloc(repository: repository);
  await bloc.start(_m1);
  return bloc;
}
