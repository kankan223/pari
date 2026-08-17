import '../../repository/domain/idempotency_key.dart';
import '../domain/sandbox_wiki.dart';
import '../domain/sandbox_wiki_records.dart';

/// In-memory [SandboxWikiRepository] for the harness and widget tests.
///
/// Same semantics as [LocalSandboxWikiRepository] (append-only revision
/// history, newest-updated-first page listing, UUID v4 id minting,
/// `SA-####` author handles) but backed by plain maps — no SQLCipher, no
/// persistence across restarts. The production wiring injects the
/// SQLCipher-backed local repository at the Phase-9 composition root.
class InMemorySandboxWikiRepository implements SandboxWikiRepository {
  final Map<String, SandboxPageRecord> _pages = {};
  final Map<String, SandboxRevisionRecord> _revisions = {};
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  InMemorySandboxWikiRepository({
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<SandboxPage>> listPages({String? moduleId}) async {
    final pages = _pages.values
        .map(_pageFromRecord)
        .where((p) => moduleId == null || p.moduleId == moduleId)
        .toList();
    pages.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pages;
  }

  @override
  Future<SandboxPage?> getPage(String pageId) async {
    final record = _pages[pageId];
    return record == null ? null : _pageFromRecord(record);
  }

  @override
  Future<List<SandboxRevision>> listRevisions(String pageId) async {
    final revisions = _revisions.values
        .where((r) => r.pageId == pageId)
        .map(_revisionFromRecord)
        .toList();
    revisions.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return revisions;
  }

  @override
  Future<SandboxPage> submitRevision({
    required String? pageId,
    required String moduleId,
    required String title,
    required String bodyMarkdown,
    required String locale,
    required String authorHandle,
  }) async {
    if (pageId == null) {
      final now = _clock();
      final id = _idGen.generate();
      _revisions[id] = SandboxRevisionRecord(
        revisionId: _idGen.generate(),
        pageId: id,
        bodyMarkdown: bodyMarkdown,
        authorHandle: authorHandle,
        createdAt: now,
      );
      final page = SandboxPageRecord(
        pageId: id,
        moduleId: moduleId,
        title: title.trim(),
        locale: locale,
        revisionCount: 1,
        updatedAt: now,
      );
      _pages[id] = page;
      return _pageFromRecord(page);
    }
    final existing = _pages[pageId];
    if (existing == null) {
      throw ArgumentError('Sandbox page not found: $pageId');
    }
    final now = _clock();
    final latest = _revisions.values.where((r) => r.pageId == pageId).toList();
    final prevId = latest.isEmpty ? null : latest.last.revisionId;
    _revisions[_idGen.generate()] = SandboxRevisionRecord(
      revisionId: _idGen.generate(),
      pageId: pageId,
      bodyMarkdown: bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: now,
      prevRevisionId: prevId,
    );
    final page = SandboxPageRecord(
      pageId: pageId,
      moduleId: existing.moduleId,
      title: title.trim(),
      locale: existing.locale,
      revisionCount: existing.revisionCount + 1,
      updatedAt: now,
    );
    _pages[pageId] = page;
    return _pageFromRecord(page);
  }

  @override
  Future<SandboxPage> revertToRevision({
    required String pageId,
    required String revisionId,
    required String authorHandle,
  }) async {
    final page = _pages[pageId];
    if (page == null) {
      throw ArgumentError('Sandbox page not found: $pageId');
    }
    final target =
        _revisions.values.where((r) => r.revisionId == revisionId).toList();
    if (target.isEmpty) {
      throw ArgumentError('Sandbox revision not found: $revisionId');
    }
    final now = _clock();
    final latest = _revisions.values.where((r) => r.pageId == pageId).toList();
    _revisions[_idGen.generate()] = SandboxRevisionRecord(
      revisionId: _idGen.generate(),
      pageId: pageId,
      bodyMarkdown: target.first.bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: now,
      prevRevisionId: latest.isEmpty ? null : latest.last.revisionId,
    );
    final updated = SandboxPageRecord(
      pageId: pageId,
      moduleId: page.moduleId,
      title: page.title,
      locale: page.locale,
      revisionCount: page.revisionCount + 1,
      updatedAt: now,
    );
    _pages[pageId] = updated;
    return _pageFromRecord(updated);
  }

  static SandboxPage _pageFromRecord(SandboxPageRecord r) => SandboxPage.parse(
        pageId: r.pageId,
        moduleId: r.moduleId,
        title: r.title,
        locale: r.locale,
        revisionCount: r.revisionCount,
        updatedAt: r.updatedAt,
      );

  static SandboxRevision _revisionFromRecord(SandboxRevisionRecord r) =>
      SandboxRevision.parse(
        revisionId: r.revisionId,
        pageId: r.pageId,
        bodyMarkdown: r.bodyMarkdown,
        authorHandle: r.authorHandle,
        createdAt: r.createdAt,
        prevRevisionId: r.prevRevisionId,
      );
}
