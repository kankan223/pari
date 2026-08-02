import 'dart:typed_data';

import 'package:civic_commons/repository/domain/message.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_message_bloc.dart';
import 'package:civic_commons/state/domain/message_state.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

void main() {
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
  });
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
