import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_message_bloc.dart';
import 'package:civic_commons/state/domain/message_cipher.dart';
import 'package:civic_commons/state/domain/message_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('MessageSummary - content semantics (Task 6.3)', () {
    test('copyWith can clear content back to null explicitly', () {
      final withContent = MessageSummary(id: 'm1', content: 'stale');

      final cleared = withContent.copyWith(content: null);

      expect(cleared.content, isNull);
    });

    test('copyWith without a content arg preserves the existing content', () {
      final withContent = MessageSummary(
        id: 'm1',
        content: 'kept',
        direction: MessageDirection.sent,
      );

      final copied = withContent.copyWith(delivered: true);

      expect(copied.content, 'kept');
      expect(copied.direction, MessageDirection.sent);
    });
  });

  group('LocalMessageBloc - state transitions (Task 3.5)', () {
    late FakeMessageRepository repository;
    late LocalDataStreamController<Message> database;
    late LocalMessageBloc bloc;
    late List<MessageState> states;

    const conversationId = 'conv-1';

    setUp(() {
      repository = FakeMessageRepository();
      database = LocalDataStreamController<Message>();
      bloc = LocalMessageBloc(
        repository: repository,
        database: database,
        conversationId: conversationId,
      );
      states = [];
      bloc.state.listen(states.add);
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    Message message(String id, {bool delivered = false}) => Message(
          id: id,
          conversationId: conversationId,
          ciphertext: Uint8List.fromList([9, 9, 9]),
          direction: MessageDirection.sent,
          delivered: delivered,
        );

    test('start() emits hasLoaded=true with messages for THIS conversation',
        () async {
      repository.seed([
        message('m1'),
        message('m2', delivered: true),
        // Belongs to another conversation — must be filtered out.
        Message(
          id: 'other',
          conversationId: 'conv-2',
          ciphertext: Uint8List(0),
          direction: MessageDirection.received,
        ),
      ]);

      await bloc.start();
      await flushMicrotasks();

      expect(states, isNotEmpty);
      expect(states.last.hasLoaded, isTrue);
      expect(states.last.conversationId, conversationId);
      expect(states.last.messages, hasLength(2));
      expect(states.last.messages.map((m) => m.id), containsAll(['m1', 'm2']));
    });

    test('database stream emission re-emits only this conversation', () async {
      repository.seed([message('m1')]);
      await bloc.start();
      await flushMicrotasks();

      database.emit([
        message('m1'),
        message('m3'),
        Message(
          id: 'other',
          conversationId: 'conv-2',
          ciphertext: Uint8List(0),
          direction: MessageDirection.received,
        ),
      ]);
      await flushMicrotasks();

      expect(states.last.messages, hasLength(2));
      expect(states.last.messages.map((m) => m.id), containsAll(['m1', 'm3']));
      expect(
        states.last.messages.map((m) => m.id),
        isNot(contains('other')),
      );
    });

    test('delivery flags are surfaced to the UI', () async {
      repository.seed([message('m1'), message('m2', delivered: true)]);
      await bloc.start();
      await flushMicrotasks();

      final byId = {for (final s in states.last.messages) s.id: s};
      expect(byId['m1']!.delivered, isFalse);
      expect(byId['m2']!.delivered, isTrue);
    });

    test('refresh() re-reads the local store and emits', () async {
      await bloc.start();
      await flushMicrotasks();

      repository.seed([message('m9')]);
      await bloc.refresh();
      await flushMicrotasks();

      expect(states.last.messages, hasLength(1));
      expect(states.last.messages.first.id, 'm9');
    });

    test('state carries ONLY UI-safe summaries, never ciphertext', () async {
      repository.seed([message('m1')]);
      await bloc.start();
      await flushMicrotasks();

      final summary = states.last.messages.single;
      expect(summary.id, 'm1');
      // MessageSummary exposes only metadata — no ciphertext member exists
      // (compile-time guarantee). Assert the projection type, not the entity.
      expect(states.last.messages.first, isA<MessageSummary>());
    });

    test('explicit direction is surfaced to the UI (Task 6.3)', () async {
      repository.seed([
        Message(
          id: 'sent1',
          conversationId: conversationId,
          ciphertext: Uint8List.fromList([1]),
          direction: MessageDirection.sent,
        ),
        Message(
          id: 'recv1',
          conversationId: conversationId,
          ciphertext: Uint8List.fromList([2]),
          direction: MessageDirection.received,
        ),
      ]);
      await bloc.start();
      await flushMicrotasks();

      final byId = {for (final s in states.last.messages) s.id: s};
      expect(byId['sent1']!.direction, MessageDirection.sent);
      expect(byId['recv1']!.direction, MessageDirection.received);
    });
  });

  group('LocalMessageBloc - decryption on emit (Task 6.3)', () {
    late FakeMessageRepository repository;
    late LocalDataStreamController<Message> database;
    late LocalMessageBloc bloc;
    late List<MessageState> states;
    late _ScriptedCipher cipher;

    const conversationId = 'conv-1';
    const peerHash =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

    setUp(() {
      repository = FakeMessageRepository();
      database = LocalDataStreamController<Message>();
      cipher = _ScriptedCipher();
      bloc = LocalMessageBloc(
        repository: repository,
        database: database,
        conversationId: conversationId,
        participantHash: peerHash,
        cipher: cipher,
      );
      states = [];
      bloc.state.listen(states.add);
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    Message message(String id,
            {MessageDirection direction = MessageDirection.received}) =>
        Message(
          id: id,
          conversationId: conversationId,
          ciphertext: Uint8List.fromList(utf8.encode('sealed-$id')),
          direction: direction,
        );

    test('decrypts each message body into the summary content', () async {
      cipher.scripted = {
        'sealed-m1': utf8.encode('Hello from the Vault'),
        'sealed-m2': utf8.encode('Second message'),
      };
      repository.seed([message('m1'), message('m2')]);

      await bloc.start();
      await flushMicrotasks();

      final byId = {for (final s in states.last.messages) s.id: s};
      expect(byId['m1']!.content, 'Hello from the Vault');
      expect(byId['m2']!.content, 'Second message');
    });

    test('a message that cannot be decrypted keeps content null', () async {
      // No scripted entry → the cipher returns null for this payload.
      repository.seed([message('m1')]);

      await bloc.start();
      await flushMicrotasks();

      expect(states.last.messages.single.content, isNull);
    });

    test('the state never carries ciphertext — only the projection', () async {
      cipher.scripted = {'sealed-m1': utf8.encode('plain')};
      repository.seed([message('m1')]);

      await bloc.start();
      await flushMicrotasks();

      final summary = states.last.messages.single;
      expect(summary, isA<MessageSummary>());
      expect(summary.content, 'plain');
      // A MessageSummary has no ciphertext member (compile-time guarantee).
    });

    test('send() encrypts, persists, and republishes the thread', () async {
      cipher.scripted = {'sealed-new': utf8.encode('outgoing text')};
      await bloc.start();
      await flushMicrotasks();

      await bloc.send('outgoing text');
      await flushMicrotasks();

      // Persisted locally as a SENT message (direction is explicit).
      final stored = (await repository.getAll()).single;
      expect(stored.direction, MessageDirection.sent);
      expect(stored.delivered, isFalse);
      // The stored body is the sealed bytes, not the plaintext.
      expect(stored.ciphertext, isNot(equals(utf8.encode('outgoing text'))));
      // The thread republished with the decrypted content.
      expect(states.last.messages.single.content, 'outgoing text');
      expect(states.last.messages.single.direction, MessageDirection.sent);
    });

    test('send() without a cipher persists raw text (dev harness fallback)', () async {
      final plain = LocalMessageBloc(
        repository: repository,
        database: database,
        conversationId: conversationId,
      );
      await plain.send('raw message');
      final all = await repository.getAll();
      expect(all.length, 1);
      expect(all.single.conversationId, conversationId);
      expect(all.single.direction, MessageDirection.sent);
      await plain.close();
    });

    test('a message that later becomes undecryptable drops its content',
        () async {
      // First emit decrypts successfully.
      cipher.scripted = {'sealed-m1': utf8.encode('fresh plaintext')};
      repository.seed([message('m1')]);
      await bloc.start();
      await flushMicrotasks();
      expect(states.last.messages.single.content, 'fresh plaintext');

      // Simulate a lost session: the cipher no longer maps the payload.
      cipher.scripted = {};
      database.emit(await repository.getAll());
      await flushMicrotasks();

      // The stale plaintext is NOT kept in state — content returns to null
      // (placeholder fallback) instead of leaking old decrypted text.
      expect(states.last.messages.single.content, isNull);
    });
  });
}

/// Scripted [MessageCipher] fake: maps ciphertext-bytes → plaintext-bytes.
class _ScriptedCipher implements MessageCipher {
  Map<String, List<int>> scripted = {};

  @override
  Future<Uint8List> encrypt({
    required String participantHash,
    required Uint8List plaintext,
  }) async {
    final sealed = utf8.encode('sealed-${utf8.decode(plaintext)}');
    scripted[utf8.decode(sealed)] = plaintext;
    return Uint8List.fromList(sealed);
  }

  @override
  Future<Uint8List?> decrypt({
    required String participantHash,
    required Uint8List ciphertext,
  }) async {
    final key = utf8.decode(ciphertext, allowMalformed: true);
    final mapped = scripted[key];
    return mapped == null ? null : Uint8List.fromList(mapped);
  }
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
