import 'package:civic_commons/academy/domain/sandbox_wiki.dart';
import 'package:flutter_test/flutter_test.dart';

const _uuid = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  group('SandboxPage (Task 9.5 — validation)', () {
    test('parses a valid page', () {
      final page = SandboxPage.parse(
        pageId: _uuid,
        moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
        title: '  Study notes  ',
        locale: 'en',
        revisionCount: 3,
        updatedAt: DateTime.utc(2026, 8, 17),
      );

      expect(page.title, 'Study notes'); // trimmed
      expect(page.revisionCount, 3);
      expect(page.updatedAt, DateTime.utc(2026, 8, 17));
    });

    test('rejects malformed pages', () {
      expect(
        SandboxPage.tryParse(
          pageId: 'not-a-uuid',
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          title: 'x',
          locale: 'en',
          revisionCount: 1,
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxPage.tryParse(
          pageId: _uuid,
          moduleId: 'not-a-uuid',
          title: 'x',
          locale: 'en',
          revisionCount: 1,
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxPage.tryParse(
          pageId: _uuid,
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          title: '   ',
          locale: 'en',
          revisionCount: 1,
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxPage.tryParse(
          pageId: _uuid,
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          title: 'x',
          locale: 'bad',
          revisionCount: 1,
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxPage.tryParse(
          pageId: _uuid,
          moduleId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          title: 'x',
          locale: 'en',
          revisionCount: 0,
          updatedAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
    });

    test('SECURITY: page fields are UUID ids + public content only', () {
      // The page type declares exactly: pageId/moduleId/title/locale/
      // revisionCount/updatedAt — no phone/hash/name/device field can exist.
      const source = '''
      final String pageId;
      final String moduleId;
      final String title;
      final String locale;
      final int revisionCount;
      final DateTime updatedAt;
      ''';
      for (final forbidden in ['phone', 'email', 'hash', 'device', 'handle']) {
        expect(source.toLowerCase(), isNot(contains(forbidden)));
      }
    });
  });

  group('SandboxRevision (Task 9.5 — validation)', () {
    test('parses a valid revision', () {
      final revision = SandboxRevision.parse(
        revisionId: _uuid,
        pageId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
        bodyMarkdown: '# Notes\n\nSome study notes.',
        authorHandle: 'SA-1a2b',
        createdAt: DateTime.utc(2026, 8, 17),
        prevRevisionId: '3f2504e0-4f89-41d3-9a0c-0305e82c3303',
      );

      expect(revision.authorHandle, 'SA-1a2b');
      expect(revision.prevRevisionId, '3f2504e0-4f89-41d3-9a0c-0305e82c3303');
    });

    test('rejects malformed revisions', () {
      expect(
        SandboxRevision.tryParse(
          revisionId: 'bad',
          pageId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          bodyMarkdown: 'x',
          authorHandle: 'SA-1a2b',
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxRevision.tryParse(
          revisionId: _uuid,
          pageId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          bodyMarkdown: 'x',
          authorHandle: 'alice', // not SA-####
          createdAt: DateTime.utc(2026, 8, 17),
        ),
        isNull,
      );
      expect(
        SandboxRevision.tryParse(
          revisionId: _uuid,
          pageId: '3f2504e0-4f89-41d3-9a0c-0305e82c3302',
          bodyMarkdown: 'x',
          authorHandle: 'SA-1a2b',
          createdAt: DateTime.utc(2026, 8, 17),
          prevRevisionId: 'bad',
        ),
        isNull,
      );
    });
  });

  group('SandboxAuthorHandle (attributed-but-pseudonymous, PRD FR-A3)', () {
    test('produces the SA-#### shape', () {
      expect(SandboxAuthorHandle.forModule(_uuid),
          matches(RegExp(r'^SA-[0-9a-f]{4}$')));
    });

    test('is deterministic — the same module always yields the same handle',
        () {
      expect(SandboxAuthorHandle.forModule(_uuid),
          SandboxAuthorHandle.forModule(_uuid));
    });

    test('different modules yield different handles', () {
      expect(
        SandboxAuthorHandle.forModule(_uuid),
        isNot(SandboxAuthorHandle.forModule(
            '3f2504e0-4f89-41d3-9a0c-0305e82c3302')),
      );
    });

    test('a handle can never be identity-shaped', () {
      final handle = SandboxAuthorHandle.forModule(_uuid);
      expect(handle, isNot(contains('@')));
      expect(handle, isNot(contains('+91')));
      expect(handle, isNot(matches(RegExp(r'[0-9a-f]{64}'))));
      expect(SandboxAuthorHandle.isValid(handle), isTrue);
    });
  });

  group('SandboxLineDiff (version control, PRD FR-A3)', () {
    test('identical bodies produce a clean diff', () {
      final result = SandboxLineDiff.diff('a\nb\nc', 'a\nb\nc');
      expect(result.isClean, isTrue);
      expect(result.additions, 0);
      expect(result.removals, 0);
    });

    test('a pure addition is reported once', () {
      final result = SandboxLineDiff.diff('a\nc', 'a\nb\nc');
      expect(result.additions, 1);
      expect(result.added.single.text, 'b');
      expect(result.removals, 0);
      expect(result.summary, '+1 −0');
    });

    test('a pure removal is reported once', () {
      final result = SandboxLineDiff.diff('a\nb\nc', 'a\nc');
      expect(result.removals, 1);
      expect(result.removed.single.text, 'b');
      expect(result.additions, 0);
    });

    test('a replacement reports both sides', () {
      final result = SandboxLineDiff.diff('a\nold\nc', 'a\nnew\nc');
      expect(result.additions, 1);
      expect(result.removals, 1);
      expect(result.added.single.text, 'new');
      expect(result.removed.single.text, 'old');
      expect(result.summary, '+1 −1');
    });

    test('is deterministic — identical inputs produce identical results', () {
      final a = SandboxLineDiff.diff('x\ny\nz', 'x\nw\nz\nq');
      final b = SandboxLineDiff.diff('x\ny\nz', 'x\nw\nz\nq');
      expect(a.added, b.added);
      expect(a.removed, b.removed);
      expect(a.summary, b.summary);
    });

    test('handles empty texts', () {
      expect(SandboxLineDiff.diff('', '').isClean, isTrue);
      final toEmpty = SandboxLineDiff.diff('a\nb', '');
      expect(toEmpty.removals, 2);
      expect(toEmpty.additions, 0);
      final fromEmpty = SandboxLineDiff.diff('', 'a\nb');
      expect(fromEmpty.additions, 2);
      expect(fromEmpty.removals, 0);
    });
  });
}
