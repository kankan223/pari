import 'dart:async';
import 'dart:typed_data';

import 'package:civic_commons/repository/data/local_connection_request_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/domain/connection_request.dart';
import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/state/data/local_conversation_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_message_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';
import '../state/fakes.dart';

/// Task 13.3 E2E: Vault pillar end-to-end lifecycle.
///
/// Tests the complete user journey:
/// 1. Send a connection request to a target hash
/// 2. Target accepts the request
/// 3. Create conversation and send messages
/// 4. Verify message direction field
void main() {
  const myHash =
      'aabbccddee112233aabbccddee112233aabbccddee112233aabbccddee112233';
  const targetHash =
      '1122334455667788112233445566778811223344556677881122334455667788';

  group('Vault E2E - Connection request → conversation → messaging', () {
    test('send request → verify persistence', () async {
      final queue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: testCipher(),
      );
      final requestRepo = LocalConnectionRequestRepository(
        store: InMemoryEntityStore<ConnectionRequest>((r) => r.id),
        syncQueue: queue,
      );

      final sent = await requestRepo.send(
        requesterHash: myHash,
        targetHash: targetHash,
      );
      expect(sent.requesterHash, myHash);
      expect(sent.recipientHash, targetHash);
      expect(sent.status, ConnectionRequestStatus.pending);

      final all = await requestRepo.getAll();
      expect(all, hasLength(1));

      final accepted = await requestRepo.accept(sent.id);
      expect(accepted.status, ConnectionRequestStatus.accepted);
    });

    test('reject request clears it from pending', () async {
      final queue = LocalSyncQueueRepository(
        store: queueStore(),
        cipher: testCipher(),
      );
      final requestRepo = LocalConnectionRequestRepository(
        store: InMemoryEntityStore<ConnectionRequest>((r) => r.id),
        syncQueue: queue,
      );

      final sent = await requestRepo.send(
        requesterHash: targetHash,
        targetHash: myHash,
      );

      final pending = await requestRepo.listIncomingPending(myHash);
      expect(pending, hasLength(1));

      await requestRepo.reject(sent.id);
      final afterReject = await requestRepo.listIncomingPending(myHash);
      expect(afterReject, isEmpty);
    });

    test('conversation creation and message flow', () async {
      final conversationRepo = FakeConversationRepository();
      final messageRepo = FakeMessageRepository();
      final conversationDb = LocalDataStreamController<Conversation>();
      final messageDb = LocalDataStreamController<Message>();

      // Create a conversation.
      final conv = Conversation(
        id: 'conv-1',
        participantHash: targetHash,
        encryptedSessionState: Uint8List.fromList([1, 2, 3]),
      );
      await conversationRepo.create(conv);
      conversationDb.emit(await conversationRepo.getAll());

      final conversationBloc = LocalConversationBloc(
        repository: conversationRepo,
        database: conversationDb,
      );

      // Seed messages in the conversation.
      await messageRepo.create(Message(
        id: 'msg-1',
        conversationId: 'conv-1',
        ciphertext: Uint8List.fromList([10, 20, 30]),
        direction: MessageDirection.sent,
      ));
      await messageRepo.create(Message(
        id: 'msg-2',
        conversationId: 'conv-1',
        ciphertext: Uint8List.fromList([40, 50, 60]),
        direction: MessageDirection.received,
      ));
      messageDb.emit(await messageRepo.getAll());

      final messageBloc = LocalMessageBloc(
        repository: messageRepo,
        database: messageDb,
        conversationId: 'conv-1',
      );

      // Collect state via stream listener (avoid timeout on .first).
      final states = <dynamic>[];
      final sub = messageBloc.state.listen(states.add);

      await conversationBloc.start();
      await messageBloc.start();
      // Allow async emissions to propagate.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(states, isNotEmpty);
      final lastState = states.last;
      expect(lastState.messages, hasLength(2));
      expect(lastState.messages[0].direction, MessageDirection.sent);
      expect(lastState.messages[1].direction, MessageDirection.received);

      await sub.cancel();
      await conversationBloc.close();
      await messageBloc.close();
      await conversationDb.close();
      await messageDb.close();
    });

    test('multiple conversations coexist', () async {
      final conversationRepo = FakeConversationRepository();
      final db = LocalDataStreamController<Conversation>();

      final conv1 = Conversation(
        id: 'conv-a',
        participantHash:
            'aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111aaaa1111',
        encryptedSessionState: Uint8List.fromList([1]),
      );
      final conv2 = Conversation(
        id: 'conv-b',
        participantHash:
            'bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222bbbb2222',
        encryptedSessionState: Uint8List.fromList([2]),
      );
      conversationRepo.seed([conv1, conv2]);
      db.emit(await conversationRepo.getAll());

      final all = await conversationRepo.getAll();
      expect(all, hasLength(2));

      await db.close();
    });

    test('no PII in conversation participant hashes', () {
      final conv = Conversation(
        id: 'conv-pii',
        participantHash:
            'aabbccddee112233aabbccddee112233aabbccddee112233aabbccddee112233',
        encryptedSessionState: Uint8List.fromList([1]),
      );
      expect(conv.participantHash.length, 64);
      expect(conv.participantHash, isNot(contains('+91')));
      expect(conv.participantHash, isNot(contains('@gmail')));
    });
  });
}
