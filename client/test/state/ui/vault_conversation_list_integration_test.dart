import 'dart:typed_data';

import 'package:civic_commons/state/data/local_conversation_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:civic_commons/state/ui/vault_conversation_list_screen.dart';
import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../state/fakes.dart';

/// VERIFY (Task 6.1): conversation list navigation through the REAL
/// [LocalConversationBloc] + [LocalDataStreamController] + fake repository —
/// the production wiring, end-to-end (mirrors the Task 5.4 integration
/// pattern).
void main() {
  const hashA =
      'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';

  Conversation conv(String id, String hash) => Conversation(
        id: id,
        participantHash: hash,
        encryptedSessionState: Uint8List.fromList([1, 2, 3]),
      );

  testWidgets('real bloc snapshot renders tiles; tap navigates to the detail',
      (tester) async {
    final repository = FakeConversationRepository()
      ..seed([
        conv('c1', hashA),
        conv('c2',
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb')
      ]);
    final database = LocalDataStreamController<Conversation>();
    final bloc = LocalConversationBloc(
      repository: repository,
      database: database,
    );
    String? opened;

    // Pump FIRST so the StreamBuilder subscribes before the bloc emits.
    await tester.pumpWidget(MaterialApp(
      home: VaultConversationListScreen(
        bloc: bloc,
        onNewConversation: () {},
        onConversationTap: (id) => opened = id,
      ),
    ));
    await bloc.start();
    await tester.pump();
    await tester.pump();

    // Both conversations render with derived, non-PII handles.
    expect(find.text(formatPeerHandle(hashA)), findsOneWidget);
    expect(find.text('Preview: [end-to-end encrypted]'), findsNWidgets(2));
    expect(find.textContaining(hashA), findsNothing);

    // Navigate to the first conversation.
    await tester.tap(find.text(formatPeerHandle(hashA)));
    await tester.pump();
    expect(opened, 'c1');

    // Database push propagates to the UI via the stream.
    database.emit([
      conv('c1', hashA),
      conv('c2',
          'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb'),
      conv('c3',
          'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc'),
    ]);
    await tester.pump();
    await tester.pump();
    expect(find.text('Preview: [end-to-end encrypted]'), findsNWidgets(3));

    // Teardown in the REAL async zone (close futures hang in the fake zone).
    await tester.runAsync(() async {
      await bloc.close();
      await database.close();
    });
  });

  testWidgets('empty database renders the empty state via the real bloc',
      (tester) async {
    final repository = FakeConversationRepository();
    final database = LocalDataStreamController<Conversation>();
    final bloc = LocalConversationBloc(
      repository: repository,
      database: database,
    );

    await tester.pumpWidget(MaterialApp(
      home: VaultConversationListScreen(bloc: bloc),
    ));
    await bloc.start();
    await tester.pump();
    await tester.pump();

    expect(find.text('No conversations yet'), findsOneWidget);

    await tester.runAsync(() async {
      await bloc.close();
      await database.close();
    });
  });
}
