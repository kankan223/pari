import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/data/local_message_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';

import 'fakes.dart';

void main() {
  late InMemoryEntityStore<Message> store;
  late LocalSyncQueueRepository queue;
  late QueuePayloadCipher cipher;
  late RecordingSyncSink sink;
  late LocalMessageRepository repo;

  setUp(() {
    store = InMemoryEntityStore((m) => m.id);
    cipher = testCipher();
    queue = LocalSyncQueueRepository(store: queueStore(), cipher: cipher);
    sink = RecordingSyncSink();
    repo = LocalMessageRepository(
      store: store,
      syncQueue: queue,
      sink: sink,
    );
  });

  Message message(String id,
          {String conversationId = 'conv1',
          Uint8List? ciphertext,
          bool delivered = false,
          DateTime? expiresAt}) =>
      Message(
        id: id,
        conversationId: conversationId,
        ciphertext:
            ciphertext ?? Uint8List.fromList(List.generate(64, (i) => i)),
        delivered: delivered,
        expiresAt: expiresAt,
      );

  group('MessageRepository - CRUD', () {
    test('create persists the message locally as undelivered', () async {
      final created = await repo.create(message('m1'));

      expect(created.delivered, isFalse);
      expect(await repo.getById('m1'), isNotNull);
      expect(store.length, 1);
    });

    test('getById returns null for an unknown message', () async {
      expect(await repo.getById('missing'), isNull);
    });

    test('getAll returns every stored message', () async {
      await repo.create(message('m1'));
      await repo.create(message('m2'));

      final all = await repo.getAll();

      expect(all.map((m) => m.id), containsAll(['m1', 'm2']));
    });

    test('update persists field changes', () async {
      await repo.create(message('m1'));
      final updated = message('m1', delivered: true);

      await repo.update(updated);

      expect((await repo.getById('m1'))!.delivered, isTrue);
    });

    test('delete removes the message', () async {
      await repo.create(message('m1'));

      await repo.delete('m1');

      expect(await repo.getById('m1'), isNull);
      expect(store.length, 0);
    });

    test('delete of an unknown message is a no-op', () async {
      await repo.delete('missing');
      expect(store.length, 0);
    });
  });

  group('MessageRepository - local-first queries', () {
    test('getByConversation returns only that conversation, oldest first',
        () async {
      await repo.create(message('m1', conversationId: 'conv1'));
      await repo.create(message('m2', conversationId: 'conv2'));
      await repo.create(message('m3', conversationId: 'conv1'));

      final conv1 = await repo.getByConversation('conv1');

      expect(conv1.map((m) => m.id), ['m1', 'm3']);
    });

    test('getUndelivered returns only locally-pending messages', () async {
      await repo.create(message('m1'));
      final delivered = message('m2', delivered: true);
      await store.insert(delivered);

      final undelivered = await repo.getUndelivered();

      expect(undelivered.map((m) => m.id), ['m1']);
    });
  });

  group('MessageRepository - mutation queueing (local-first write)', () {
    test('create enqueues a pending create item carrying only ciphertext',
        () async {
      final ct = Uint8List.fromList(List.generate(64, (i) => i));
      await repo.create(message('m1', ciphertext: ct));

      final pending = await queue.getPending();

      expect(pending, hasLength(1));
      expect(pending.first.operationType, SyncOperationType.create);
      // The queued payload is the SEALED ciphertext — it decrypts back to
      // the original message ciphertext (Task 3.3 checkpoint).
      expect(pending.first.payload, isNot(equals(ct)));
      expect(await cipher.open(pending.first.payload), equals(ct));
    });

    test('update enqueues a pending update item', () async {
      await repo.create(message('m1'));
      sink.pushed.clear();

      await repo.update(message('m1'));

      final pending = await queue.getPending();
      expect(pending.last.operationType, SyncOperationType.update);
    });

    test('delete enqueues a pending delete item', () async {
      await repo.create(message('m1'));
      sink.pushed.clear();

      await repo.delete('m1');

      final pending = await queue.getPending();
      expect(pending.last.operationType, SyncOperationType.delete);
    });
  });
}
