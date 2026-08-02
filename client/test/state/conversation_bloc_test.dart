import 'dart:typed_data';

import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/state/data/local_conversation_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/domain/conversation_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
  group('LocalConversationBloc - state transitions (Task 3.5)', () {
    late FakeConversationRepository repository;
    late LocalDataStreamController<Conversation> database;
    late LocalConversationBloc bloc;
    late List<ConversationState> states;

    setUp(() {
      repository = FakeConversationRepository();
      database = LocalDataStreamController<Conversation>();
      bloc = LocalConversationBloc(repository: repository, database: database);
      states = [];
      bloc.state.listen(states.add);
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    test('start() emits hasLoaded=true with the initial local snapshot',
        () async {
      repository.seed([
        Conversation(
          id: 'c1',
          participantHash: 'hash-1',
          encryptedSessionState: Uint8List(0),
        ),
      ]);

      await bloc.start();
      await flushMicrotasks();

      expect(states, isNotEmpty);
      expect(states.last.hasLoaded, isTrue);
      expect(states.last.conversations, hasLength(1));
      expect(states.last.conversations.first.id, 'c1');
      expect(states.last.conversations.first.participantHash, 'hash-1');
    });

    test('start() emits an empty (hasLoaded) state when the vault is empty',
        () async {
      await bloc.start();
      await flushMicrotasks();

      expect(states.last.hasLoaded, isTrue);
      expect(states.last.conversations, isEmpty);
    });

    test('database stream emission triggers a fresh BLoC emission', () async {
      repository.seed([
        Conversation(
          id: 'c1',
          participantHash: 'hash-1',
          encryptedSessionState: Uint8List(0),
        ),
      ]);
      await bloc.start();
      await flushMicrotasks();

      // A database change pushes a new snapshot.
      database.emit([
        Conversation(
          id: 'c1',
          participantHash: 'hash-1',
          encryptedSessionState: Uint8List(0),
        ),
        Conversation(
          id: 'c2',
          participantHash: 'hash-2',
          encryptedSessionState: Uint8List(0),
        ),
      ]);
      await flushMicrotasks();

      expect(states.last.conversations, hasLength(2));
      expect(states.last.conversations.map((c) => c.id), contains('c2'));
    });

    test('refresh() re-reads the local store and emits', () async {
      await bloc.start();
      await flushMicrotasks();

      repository.seed([
        Conversation(
          id: 'c9',
          participantHash: 'hash-9',
          encryptedSessionState: Uint8List(0),
        ),
      ]);
      await bloc.refresh();
      await flushMicrotasks();

      expect(states.last.conversations, hasLength(1));
      expect(states.last.conversations.first.id, 'c9');
    });

    test('state carries ONLY UI-safe summaries, never session ciphertext',
        () async {
      repository.seed([
        Conversation(
          id: 'c1',
          participantHash: 'hash-1',
          encryptedSessionState: Uint8List.fromList([1, 2, 3]),
        ),
      ]);

      await bloc.start();
      await flushMicrotasks();

      final summary = states.last.conversations.single;
      expect(summary.id, 'c1');
      expect(summary.participantHash, 'hash-1');
      // ConversationSummary is a UI projection — no ciphertext member exists
      // (compile-time guarantee). Assert the full entity is never leaked.
      expect(states.last.conversations.first, isA<ConversationSummary>());
    });
  });
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
