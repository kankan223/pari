import '../../repository/domain/sync_queue_item.dart';
import '../../repository/domain/sync_queue_repository.dart';
import '../domain/sandbox_wiki.dart';
import '../domain/sandbox_wiki_wire_codec.dart';

/// Sealed sync wrapper around [SandboxWikiRepository] (Task 9.5).
///
/// Every submitted revision is persisted locally FIRST (offline-first, via
/// the injected [SandboxWikiRepository] — the SQLCipher-backed local rows)
/// and then a [SyncQueueItem] is enqueued with the serialized revision
/// frame; the [SyncQueueRepository] SEALS the payload with the AES-256-GCM
/// queue cipher BEFORE storage (SECURITY CHECKPOINT Task 9.5: Sandbox
/// edits are encrypted before sync) — the queue never persists plaintext
/// wiki bodies.
///
/// Reads delegate to the local repository; writes are local-first + queued.
class QueueSandboxRevisionSink implements SandboxWikiRepository {
  final SandboxWikiRepository _local;
  final SyncQueueRepository _syncQueue;

  QueueSandboxRevisionSink({
    required SandboxWikiRepository local,
    required SyncQueueRepository syncQueue,
  })  : _local = local,
        _syncQueue = syncQueue;

  @override
  Future<List<SandboxPage>> listPages({String? moduleId}) =>
      _local.listPages(moduleId: moduleId);

  @override
  Future<SandboxPage?> getPage(String pageId) => _local.getPage(pageId);

  @override
  Future<List<SandboxRevision>> listRevisions(String pageId) =>
      _local.listRevisions(pageId);

  @override
  Future<SandboxPage> submitRevision({
    required String? pageId,
    required String moduleId,
    required String title,
    required String bodyMarkdown,
    required String locale,
    required String authorHandle,
  }) async {
    // 1. Local-first write — persist inside the encrypted DB immediately.
    final page = await _local.submitRevision(
      pageId: pageId,
      moduleId: moduleId,
      title: title,
      bodyMarkdown: bodyMarkdown,
      locale: locale,
      authorHandle: authorHandle,
    );
    // 2. Queue the mutation — the frame carries ONLY UUID ids + public
    //    fields + the SA-#### handle, SEALED by the queue repository.
    final revisions = await _local.listRevisions(page.pageId);
    final latest = revisions.last;
    final frame = SandboxRevisionWireFrame(
      pageId: page.pageId,
      moduleId: page.moduleId,
      title: page.title,
      bodyMarkdown: latest.bodyMarkdown,
      authorHandle: latest.authorHandle,
      createdAtMs: latest.createdAt.millisecondsSinceEpoch,
    );
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: encodeSandboxRevisionFrame(frame),
    );
    return page;
  }

  @override
  Future<SandboxPage> revertToRevision({
    required String pageId,
    required String revisionId,
    required String authorHandle,
  }) async {
    final page = await _local.revertToRevision(
      pageId: pageId,
      revisionId: revisionId,
      authorHandle: authorHandle,
    );
    final revisions = await _local.listRevisions(page.pageId);
    final latest = revisions.last;
    final frame = SandboxRevisionWireFrame(
      pageId: page.pageId,
      moduleId: page.moduleId,
      title: page.title,
      bodyMarkdown: latest.bodyMarkdown,
      authorHandle: latest.authorHandle,
      createdAtMs: latest.createdAt.millisecondsSinceEpoch,
    );
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: encodeSandboxRevisionFrame(frame),
    );
    return page;
  }
}
