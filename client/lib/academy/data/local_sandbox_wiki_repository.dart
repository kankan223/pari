import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../domain/sandbox_wiki.dart';
import '../domain/sandbox_wiki_records.dart';

/// Production [SandboxWikiRepository] (Task 9.5 — Sandbox Wiki System).
///
/// Persists pages + the append-only revision history inside the encrypted
/// SQLCipher database (`sandbox_pages` + `sandbox_revisions`, schema v12).
/// OFFLINE-FIRST: the local rows are written before anything else — a
/// submitted revision lands in the encrypted partition immediately and the
/// sealed sync enqueue happens through the wrapping [QueueSandboxRevisionSink].
///
/// SECURITY CHECKPOINT (Task 9.5): every page/revision id is a minted UUID
/// v4; author handles are the deterministic `SA-####` pseudonymous handles
/// — zero identity ever enters these rows; the Markdown body is community
/// UGC persisted only inside the encrypted partition (sensitive column).
class LocalSandboxWikiRepository implements SandboxWikiRepository {
  final EntityStore<SandboxPageRecord> _pageStore;
  final EntityStore<SandboxRevisionRecord> _revisionStore;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;

  LocalSandboxWikiRepository({
    required EntityStore<SandboxPageRecord> pageStore,
    required EntityStore<SandboxRevisionRecord> revisionStore,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
  })  : _pageStore = pageStore,
        _revisionStore = revisionStore,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now;

  @override
  Future<List<SandboxPage>> listPages({String? moduleId}) async {
    final records = await _pageStore.getAll();
    final pages = records
        .map(_pageFromRecord)
        .where((p) => moduleId == null || p.moduleId == moduleId)
        .toList();
    // Newest-updated first.
    pages.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return pages;
  }

  @override
  Future<SandboxPage?> getPage(String pageId) async {
    final record = await _pageStore.getById(pageId);
    return record == null ? null : _pageFromRecord(record);
  }

  @override
  Future<List<SandboxRevision>> listRevisions(String pageId) async {
    final records = await _revisionStore.getAll();
    final revisions = records
        .where((r) => r.pageId == pageId)
        .map(_revisionFromRecord)
        .toList();
    // Oldest first (the version chain order).
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
      return _createPage(
        moduleId: moduleId,
        title: title,
        bodyMarkdown: bodyMarkdown,
        locale: locale,
        authorHandle: authorHandle,
      );
    }
    final existing = await _pageStore.getById(pageId);
    if (existing == null) {
      throw ArgumentError('Sandbox page not found: $pageId');
    }
    final now = _clock();
    final previous = (await _revisionStore.getAll())
        .where((r) => r.pageId == pageId)
        .map((r) => r.revisionId)
        .toList();
    final prevId = previous.isEmpty ? null : previous.last;
    // Local-first: the revision row lands first, then the page aggregate.
    await _revisionStore.insert(SandboxRevisionRecord(
      revisionId: _idGen.generate(),
      pageId: pageId,
      bodyMarkdown: bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: now,
      prevRevisionId: prevId,
    ));
    await _pageStore.update(SandboxPageRecord(
      pageId: pageId,
      moduleId: existing.moduleId,
      title: title.trim(),
      locale: existing.locale,
      revisionCount: existing.revisionCount + 1,
      updatedAt: now,
    ));
    return (await getPage(pageId))!;
  }

  Future<SandboxPage> _createPage({
    required String moduleId,
    required String title,
    required String bodyMarkdown,
    required String locale,
    required String authorHandle,
  }) async {
    final now = _clock();
    final pageId = _idGen.generate();
    await _revisionStore.insert(SandboxRevisionRecord(
      revisionId: _idGen.generate(),
      pageId: pageId,
      bodyMarkdown: bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: now,
    ));
    await _pageStore.insert(SandboxPageRecord(
      pageId: pageId,
      moduleId: moduleId,
      title: title.trim(),
      locale: locale,
      revisionCount: 1,
      updatedAt: now,
    ));
    return (await getPage(pageId))!;
  }

  @override
  Future<SandboxPage> revertToRevision({
    required String pageId,
    required String revisionId,
    required String authorHandle,
  }) async {
    final page = await _pageStore.getById(pageId);
    if (page == null) {
      throw ArgumentError('Sandbox page not found: $pageId');
    }
    final all = await _revisionStore.getAll();
    final target = all.where((r) => r.revisionId == revisionId).toList();
    if (target.isEmpty) {
      throw ArgumentError('Sandbox revision not found: $revisionId');
    }
    final now = _clock();
    final latestId =
        all.where((r) => r.pageId == pageId).map((r) => r.revisionId).toList();
    await _revisionStore.insert(SandboxRevisionRecord(
      revisionId: _idGen.generate(),
      pageId: pageId,
      bodyMarkdown: target.first.bodyMarkdown,
      authorHandle: authorHandle,
      createdAt: now,
      prevRevisionId: latestId.isEmpty ? null : latestId.last,
    ));
    await _pageStore.update(SandboxPageRecord(
      pageId: pageId,
      moduleId: page.moduleId,
      title: page.title,
      locale: page.locale,
      revisionCount: page.revisionCount + 1,
      updatedAt: now,
    ));
    return (await getPage(pageId))!;
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
