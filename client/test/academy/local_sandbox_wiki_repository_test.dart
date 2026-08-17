import 'package:civic_commons/academy/data/local_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki_records.dart';
import 'package:civic_commons/repository/data/sqlite_entity_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';
const _m2 = '3f2504e0-4f89-41d3-9a0c-0305e82c3302';

var _clockMs = 1755468000000;
DateTime _clock() => DateTime.fromMillisecondsSinceEpoch(_clockMs, isUtc: true);

LocalSandboxWikiRepository _repo(
  InMemoryEntityStore<SandboxPageRecord> pages,
  InMemoryEntityStore<SandboxRevisionRecord> revisions,
) =>
    LocalSandboxWikiRepository(
      pageStore: pages,
      revisionStore: revisions,
      clock: _clock,
    );

void main() {
  setUp(() => _clockMs = 1755468000000);

  group('LocalSandboxWikiRepository (Task 9.5 — offline-first)', () {
    test('first submit creates the page + first revision', () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );

      final page = await repo.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Civic Rights Notes',
        bodyMarkdown: '# Notes',
        locale: 'en',
        authorHandle: SandboxAuthorHandle.forModule(_m1),
      );

      expect(
          page.pageId,
          matches(RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')));
      expect(page.moduleId, _m1);
      expect(page.revisionCount, 1);
      final revisions = await repo.listRevisions(page.pageId);
      expect(revisions, hasLength(1));
      expect(revisions.single.bodyMarkdown, '# Notes');
      expect(revisions.single.authorHandle, SandboxAuthorHandle.forModule(_m1));
      expect(revisions.single.prevRevisionId, isNull);
    });

    test('subsequent submits append revisions and bump the count', () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final page = await repo.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Notes',
        bodyMarkdown: 'v1',
        locale: 'en',
        authorHandle: 'SA-1a2b',
      );

      _clockMs += 60000;
      final updated = await repo.submitRevision(
        pageId: page.pageId,
        moduleId: _m1,
        title: 'Notes (edited)',
        bodyMarkdown: 'v2',
        locale: 'en',
        authorHandle: 'SA-1a2b',
      );

      expect(updated.revisionCount, 2);
      expect(updated.title, 'Notes (edited)');
      final revisions = await repo.listRevisions(updated.pageId);
      expect(revisions, hasLength(2));
      expect(revisions.last.prevRevisionId, revisions.first.revisionId);
    });

    test('listPages is module-scoped and newest-updated first', () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final p1 = await repo.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'A',
          bodyMarkdown: 'a',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      _clockMs += 60000;
      final p2 = await repo.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'B',
          bodyMarkdown: 'b',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      _clockMs += 60000;
      await repo.submitRevision(
          pageId: null,
          moduleId: _m2,
          title: 'Other',
          bodyMarkdown: 'o',
          locale: 'en',
          authorHandle: 'SA-2b3c');

      final m1Pages = await repo.listPages(moduleId: _m1);
      expect(
          m1Pages.map((p) => p.pageId), [p2.pageId, p1.pageId]); // newest first
      final all = await repo.listPages();
      expect(all, hasLength(3));
    });

    test('getPage returns null for an unknown page', () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      expect(await repo.getPage(_m1), isNull);
    });

    test('revert appends a revision with the target body (append-only)',
        () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final page = await repo.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v1',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      _clockMs += 60000;
      await repo.submitRevision(
          pageId: page.pageId,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v2',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      final revisions = await repo.listRevisions(page.pageId);

      _clockMs += 60000;
      final reverted = await repo.revertToRevision(
        pageId: page.pageId,
        revisionId: revisions.first.revisionId, // back to v1
        authorHandle: 'SA-1a2b',
      );

      expect(reverted.revisionCount, 3);
      final after = await repo.listRevisions(page.pageId);
      expect(after, hasLength(3));
      expect(after.last.bodyMarkdown, 'v1'); // the reverted body
      expect(after.last.prevRevisionId, revisions.last.revisionId);
      // The history is append-only — the original rows are untouched.
      expect(after.first.bodyMarkdown, 'v1');
      expect(after[1].bodyMarkdown, 'v2');
    });

    test('reverting to an unknown revision / page throws', () async {
      final repo = _repo(
        InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final page = await repo.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v1',
          locale: 'en',
          authorHandle: 'SA-1a2b');

      expect(
        () => repo.revertToRevision(
            pageId: page.pageId, revisionId: _m2, authorHandle: 'SA-1a2b'),
        throwsArgumentError,
      );
      expect(
        () => repo.revertToRevision(
            pageId: _m2, revisionId: page.pageId, authorHandle: 'SA-1a2b'),
        throwsArgumentError,
      );
      expect(
        () => repo.submitRevision(
            pageId: _m2,
            moduleId: _m1,
            title: 'x',
            bodyMarkdown: 'x',
            locale: 'en',
            authorHandle: 'SA-1a2b'),
        throwsArgumentError,
      );
    });

    test('COLD RESTART: pages + revisions restore from the same stores',
        () async {
      final pages = InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId);
      final revisions =
          InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId);
      final repo = _repo(pages, revisions);
      final page = await repo.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v1',
          locale: 'en',
          authorHandle: 'SA-1a2b');

      // Fresh repository over the SAME stores (persisted rows).
      final restarted = _repo(pages, revisions);
      final loaded = await restarted.getPage(page.pageId);
      expect(loaded, isNotNull);
      expect(loaded!.revisionCount, 1);
      final history = await restarted.listRevisions(page.pageId);
      expect(history.single.bodyMarkdown, 'v1');
      expect((await restarted.listPages(moduleId: _m1)), hasLength(1));
    });
  });

  group('sandbox row codecs (Task 9.5 — strict bounds)', () {
    test('page codec round-trips (UTC-preserving timestamp)', () {
      final record = SandboxPageRecord(
        pageId: _m1,
        moduleId: _m2,
        title: 'Notes',
        locale: 'en',
        revisionCount: 4,
        updatedAt: DateTime.fromMillisecondsSinceEpoch(_clockMs, isUtc: true),
      );

      final back = sandboxPageRecordFromRow(sandboxPageRecordToRow(record));

      expect(back.pageId, _m1);
      expect(back.moduleId, _m2);
      expect(back.revisionCount, 4);
      expect(back.updatedAt,
          DateTime.fromMillisecondsSinceEpoch(_clockMs, isUtc: true));
    });

    test('page read path re-validates: non-UUID ids throw', () {
      expect(
        () => sandboxPageRecordFromRow({
          'page_id': 'not-a-uuid',
          'module_id': _m2,
          'title': 'x',
          'locale': 'en',
          'revision_count': 1,
          'updated_at': 1,
        }),
        throwsArgumentError,
      );
    });

    test('revision codec round-trips including prev_revision_id', () {
      final record = SandboxRevisionRecord(
        revisionId: _m1,
        pageId: _m2,
        bodyMarkdown: '# Notes',
        authorHandle: 'SA-1a2b',
        createdAt: DateTime.fromMillisecondsSinceEpoch(_clockMs, isUtc: true),
        prevRevisionId: '3f2504e0-4f89-41d3-9a0c-0305e82c3303',
      );

      final back =
          sandboxRevisionRecordFromRow(sandboxRevisionRecordToRow(record));

      expect(back.bodyMarkdown, '# Notes');
      expect(back.authorHandle, 'SA-1a2b');
      expect(back.prevRevisionId, '3f2504e0-4f89-41d3-9a0c-0305e82c3303');
    });

    test('revision read path re-validates: malformed author handle throws', () {
      expect(
        () => sandboxRevisionRecordFromRow({
          'revision_id': _m1,
          'page_id': _m2,
          'body_markdown': 'x',
          'author_handle': 'alice',
          'created_at': 1,
        }),
        throwsArgumentError,
      );
      expect(
        () => sandboxRevisionRecordFromRow({
          'revision_id': 'bad',
          'page_id': _m2,
          'body_markdown': 'x',
          'author_handle': 'SA-1a2b',
          'created_at': 1,
        }),
        throwsArgumentError,
      );
    });
  });
}
