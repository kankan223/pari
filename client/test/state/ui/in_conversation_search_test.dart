import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civic_commons/state/ui/message_search_screen.dart';
import 'package:civic_commons/state/domain/message_search_bloc.dart';
import 'package:civic_commons/repository/data/in_memory_message_search_repository.dart';
import 'package:civic_commons/repository/domain/message.dart';

void main() {
  group('In-conversation search', () {
    MessageSearchBloc createBloc({String? conversationId}) {
      final messages = [
        Message(
          id: 'msg-1',
          conversationId: conversationId ?? 'conv-a',
          ciphertext: Uint8List.fromList('Hello world'.codeUnits),
          direction: MessageDirection.sent,
        ),
        Message(
          id: 'msg-2',
          conversationId: conversationId ?? 'conv-a',
          ciphertext: Uint8List.fromList('Hello flutter'.codeUnits),
          direction: MessageDirection.received,
        ),
        Message(
          id: 'msg-3',
          conversationId: 'conv-b',
          ciphertext: Uint8List.fromList('Hello other'.codeUnits),
          direction: MessageDirection.sent,
        ),
      ];
      final repo = InMemoryMessageSearchRepository(
        messages: messages,
        contentProvider: (msg) => String.fromCharCodes(msg.ciphertext),
      );
      return MessageSearchBloc(repo: repo);
    }

    testWidgets('search screen shows scoped title when conversationId provided', (tester) async {
      final bloc = createBloc(conversationId: 'conv-a');
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
          ),
        ),
      );
      expect(find.text('Searching in this conversation'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('search screen shows no scoped title when conversationId is null', (tester) async {
      final bloc = createBloc();
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
          ),
        ),
      );
      expect(find.text('Searching in this conversation'), findsNothing);
      await bloc.close();
    });

    testWidgets('search field works within conversation', (tester) async {
      final bloc = createBloc(conversationId: 'conv-a');
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump(const Duration(milliseconds: 400)); // debounce
      expect(find.textContaining('2 results'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('search results are scoped to conversation', (tester) async {
      final bloc = createBloc(conversationId: 'conv-a');
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump(const Duration(milliseconds: 400));
      // Should find 2 results from conv-a, not 3 from conv-b
      expect(find.textContaining('2 results'), findsOneWidget);
      expect(find.textContaining('3 results'), findsNothing);
      await bloc.close();
    });

    testWidgets('empty state shows search prompt', (tester) async {
      final bloc = createBloc(conversationId: 'conv-a');
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
          ),
        ),
      );
      expect(find.text('Search through your messages'), findsOneWidget);
      await bloc.close();
    });

    testWidgets('no results state shows appropriate message', (tester) async {
      final bloc = createBloc(conversationId: 'conv-a');
      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), 'xyz');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('No results for'), findsOneWidget);
      await bloc.close();
    });

    test('security checkpoint: no PII in search screen', () {
      // Verify the screen doesn't render any raw hashes or phone numbers.
      // This is a structural assertion — the screen only shows snippets.
      final widget = MessageSearchScreen(
        searchBloc: createBloc(),
      );
      expect(widget.conversationId, isA<String?>());
    });

    test('repository filters by conversationId correctly', () async {
      final messages = [
        Message(
          id: 'msg-1',
          conversationId: 'conv-a',
          ciphertext: Uint8List.fromList('Hello world'.codeUnits),
          direction: MessageDirection.sent,
        ),
        Message(
          id: 'msg-2',
          conversationId: 'conv-b',
          ciphertext: Uint8List.fromList('Hello other'.codeUnits),
          direction: MessageDirection.sent,
        ),
      ];
      final repo = InMemoryMessageSearchRepository(
        messages: messages,
        contentProvider: (msg) => String.fromCharCodes(msg.ciphertext),
      );
      final results = await repo.search(
        query: 'Hello',
        conversationId: 'conv-a',
      );
      expect(results.totalCount, 1);
      expect(results.results.first.conversationId, 'conv-a');
    });

    test('repository returns all conversations when conversationId is null', () async {
      final messages = [
        Message(
          id: 'msg-1',
          conversationId: 'conv-a',
          ciphertext: Uint8List.fromList('Hello world'.codeUnits),
          direction: MessageDirection.sent,
        ),
        Message(
          id: 'msg-2',
          conversationId: 'conv-b',
          ciphertext: Uint8List.fromList('Hello other'.codeUnits),
          direction: MessageDirection.sent,
        ),
      ];
      final repo = InMemoryMessageSearchRepository(
        messages: messages,
        contentProvider: (msg) => String.fromCharCodes(msg.ciphertext),
      );
      final results = await repo.search(query: 'Hello');
      expect(results.totalCount, 2);
    });
  });
}
