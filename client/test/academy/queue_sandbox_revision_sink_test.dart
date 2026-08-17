import 'package:civic_commons/academy/data/local_sandbox_wiki_repository.dart';
import 'package:civic_commons/academy/data/queue_sandbox_revision_sink.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki_records.dart';
import 'package:civic_commons/academy/domain/sandbox_wiki_wire_codec.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

const _m1 = '3f2504e0-4f89-41d3-9a0c-0305e82c3301';

void main() {
  group('QueueSandboxRevisionSink (Task 9.5 — encrypted before sync)', () {
    test('submit is local-first AND enqueues a SEALED revision frame',
        () async {
      final cipher = testCipher(); // real fast AES-256-GCM
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: cipher,
      );
      final local = LocalSandboxWikiRepository(
        pageStore: InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        revisionStore:
            InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final sink = QueueSandboxRevisionSink(local: local, syncQueue: syncQueue);

      final page = await sink.submitRevision(
        pageId: null,
        moduleId: _m1,
        title: 'Civic Rights Notes',
        bodyMarkdown: '# Heading\n\nSome **notes**.',
        locale: 'en',
        authorHandle: 'SA-1a2b',
      );

      // 1. Local-first: the page + revision exist immediately.
      expect(await local.getPage(page.pageId), isNotNull);
      expect(await local.listRevisions(page.pageId), hasLength(1));

      // 2. One sealed queue item is enqueued.
      final pending = await syncQueue.getPending();
      expect(pending, hasLength(1));

      // 3. Opening the sealed payload yields the exact revision frame.
      final opened = await cipher.open(pending.single.payload);
      final frame = decodeSandboxRevisionFrame(opened);
      expect(frame.pageId, page.pageId);
      expect(frame.moduleId, _m1);
      expect(frame.title, 'Civic Rights Notes');
      expect(frame.bodyMarkdown, '# Heading\n\nSome **notes**.');
      expect(frame.authorHandle, 'SA-1a2b');
      expect(frame.createdAtMs, greaterThan(0));

      // 4. BYTE-LEVEL: the STORED queue payload is ciphertext — it can
      //    never equal the plaintext frame bytes the sink would have
      //    serialized (re-encoded from the opened frame).
      final plaintext = encodeSandboxRevisionFrame(frame);
      expect(pending.single.payload, isNot(equals(plaintext)));
      // The queue repository holds ONLY the sealed bytes.
      expect(pending.single.payload, isNotEmpty);
    });

    test('revert enqueues an additional sealed revision', () async {
      final cipher = testCipher();
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: cipher,
      );
      final local = LocalSandboxWikiRepository(
        pageStore: InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        revisionStore:
            InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final sink = QueueSandboxRevisionSink(local: local, syncQueue: syncQueue);

      final page = await sink.submitRevision(
          pageId: null,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v1',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      await sink.submitRevision(
          pageId: page.pageId,
          moduleId: _m1,
          title: 'Notes',
          bodyMarkdown: 'v2',
          locale: 'en',
          authorHandle: 'SA-1a2b');
      final revisions = await local.listRevisions(page.pageId);

      await sink.revertToRevision(
        pageId: page.pageId,
        revisionId: revisions.first.revisionId,
        authorHandle: 'SA-1a2b',
      );

      final pending = await syncQueue.getPending();
      expect(pending, hasLength(3)); // v1 + v2 + revert
      // The revert envelope opens to the reverted (v1) body.
      final opened = await cipher.open(pending.last.payload);
      final frame = decodeSandboxRevisionFrame(opened);
      expect(frame.bodyMarkdown, 'v1');
    });

    test('reads delegate to the local repository', () async {
      final cipher = testCipher();
      final syncQueue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: cipher,
      );
      final local = LocalSandboxWikiRepository(
        pageStore: InMemoryEntityStore<SandboxPageRecord>((r) => r.pageId),
        revisionStore:
            InMemoryEntityStore<SandboxRevisionRecord>((r) => r.revisionId),
      );
      final sink = QueueSandboxRevisionSink(local: local, syncQueue: syncQueue);

      expect(await sink.listPages(moduleId: _m1), isEmpty);
      expect(await sink.getPage(_m1), isNull);
      expect(await sink.listRevisions(_m1), isEmpty);
    });
  });
}
