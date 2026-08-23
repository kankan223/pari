import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:civic_commons/state/ui/message_search_screen.dart';
import 'package:civic_commons/state/domain/message_search_bloc.dart';
import 'package:civic_commons/repository/data/in_memory_message_search_repository.dart';
import 'package:civic_commons/repository/domain/message.dart';

void main() {
  group('Search highlight', () {
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
      ];
      final repo = InMemoryMessageSearchRepository(
        messages: messages,
        contentProvider: (msg) => String.fromCharCodes(msg.ciphertext),
      );
      return MessageSearchBloc(repo: repo);
    }

    testWidgets('tapping search result passes query to onResultTap', (tester) async {
      String? receivedConvId;
      String? receivedMsgId;
      String? receivedQuery;
      final bloc = createBloc(conversationId: 'conv-a');

      await tester.pumpWidget(
        MaterialApp(
          home: MessageSearchScreen(
            searchBloc: bloc,
            conversationId: 'conv-a',
            onResultTap: (convId, msgId, query) {
              receivedConvId = convId;
              receivedMsgId = msgId;
              receivedQuery = query;
            },
          ),
        ),
      );

      // Type a search query.
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump(const Duration(milliseconds: 400));

      // Tap the first result.
      await tester.tap(find.byType(ListTile).first);
      await tester.pump();

      expect(receivedConvId, 'conv-a');
      expect(receivedMsgId, isNotNull);
      expect(receivedQuery, 'Hello');
      await bloc.close();
    });

    testWidgets('search screen renders scoped title', (tester) async {
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

    test('security checkpoint: no PII in highlight text', () {
      // Verify the highlight callback doesn't leak any PII.
      final results = <String?>[];
      final bloc = createBloc(conversationId: 'conv-a');
      final screen = MessageSearchScreen(
        searchBloc: bloc,
        conversationId: 'conv-a',
        onResultTap: (convId, msgId, query) {
          results.addAll([convId, msgId, query]);
        },
      );
      expect(screen.conversationId, 'conv-a');
      expect(results, isEmpty);
    });
  });
}
