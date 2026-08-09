import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_conversation_repository.dart';
import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';

import 'fakes.dart';

void main() {
  late InMemoryEntityStore<Conversation> store;
  late LocalSyncQueueRepository queue;
  late QueuePayloadCipher cipher;
  late RecordingSyncSink sink;
  late LocalConversationRepository repo;

  setUp(() {
    store = InMemoryEntityStore((c) => c.id);
    cipher = testCipher();
    queue = LocalSyncQueueRepository(store: queueStore(), cipher: cipher);
    sink = RecordingSyncSink();
    repo = LocalConversationRepository(
      store: store,
      syncQueue: queue,
      sink: sink,
    );
  });

  Conversation conversation(String id,
          {String? participantHash, Uint8List? sessionState}) =>
      Conversation(
        id: id,
        participantHash: participantHash ?? 'blindhash-$id',
        encryptedSessionState:
            sessionState ?? Uint8List.fromList(List.generate(32, (i) => i)),
      );

  group('ConversationRepository - CRUD', () {
    test('create persists the conversation locally', () async {
      final created = await repo.create(conversation('c1'));

      expect(created.id, 'c1');
      expect(await repo.getById('c1'), isNotNull);
      expect(store.length, 1);
    });

    test('getById returns null for an unknown conversation', () async {
      expect(await repo.getById('missing'), isNull);
    });

    test('getAll returns every conversation', () async {
      await repo.create(conversation('c1'));
      await repo.create(conversation('c2'));

      final all = await repo.getAll();

      expect(all.map((c) => c.id), containsAll(['c1', 'c2']));
    });

    test('update replaces the stored conversation', () async {
      await repo.create(conversation('c1'));
      final updated = conversation('c1', participantHash: 'blindhash-new');

      await repo.update(updated);

      final stored = await repo.getById('c1');
      expect(stored!.participantHash, 'blindhash-new');
    });

    test('delete removes the conversation', () async {
      await repo.create(conversation('c1'));

      await repo.delete('c1');

      expect(await repo.getById('c1'), isNull);
      expect(store.length, 0);
    });

    test('delete of an unknown conversation is a no-op', () async {
      await repo.delete('missing');
      expect(store.length, 0);
    });
  });

  group('ConversationRepository - Vault queries', () {
    test('getByParticipantHash finds the matching conversation', () async {
      await repo.create(conversation('c1', participantHash: 'blindhash-a'));
      await repo.create(conversation('c2', participantHash: 'blindhash-b'));

      final found = await repo.getByParticipantHash('blindhash-b');

      expect(found!.id, 'c2');
    });

    test('getByParticipantHash returns null when absent', () async {
      await repo.create(conversation('c1', participantHash: 'blindhash-a'));

      expect(await repo.getByParticipantHash('blindhash-zzz'), isNull);
    });
  });

  group('ConversationRepository - mutation queueing (local-first write)', () {
    test('create enqueues a pending create item with opaque session state',
        () async {
      final state = Uint8List.fromList(List.generate(48, (i) => i));
      await repo.create(conversation('c1', sessionState: state));

      final pending = await queue.getPending();

      expect(pending, hasLength(1));
      expect(pending.first.operationType, SyncOperationType.create);
      // The queued payload is SEALED — decrypts back to the session state.
      expect(pending.first.payload, isNot(equals(state)));
      expect(await cipher.open(pending.first.payload), equals(state));
    });

    test('update enqueues a pending update item', () async {
      await repo.create(conversation('c1'));
      sink.pushed.clear();

      await repo.update(conversation('c1'));

      final pending = await queue.getPending();
      expect(pending.last.operationType, SyncOperationType.update);
    });

    test('delete enqueues a pending delete item', () async {
      await repo.create(conversation('c1'));
      sink.pushed.clear();

      await repo.delete('c1');

      final pending = await queue.getPending();
      expect(pending.last.operationType, SyncOperationType.delete);
    });
  });
}
