import 'dart:async';
import 'dart:typed_data';

import 'package:civic_commons/repository/data/local_connection_request_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/memory_username_directory.dart';
import 'package:civic_commons/repository/domain/connection_request.dart';
import 'package:civic_commons/repository/domain/conversation.dart';
import 'package:civic_commons/state/data/local_connection_requests_bloc.dart';
import 'package:civic_commons/state/data/local_conversation_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/domain/conversation_bloc.dart';
import 'package:civic_commons/state/domain/conversation_state.dart';
import 'package:civic_commons/state/domain/peer_handle.dart';
import 'package:civic_commons/state/ui/vault_conversation_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repository/fakes.dart';
import '../../state/fakes.dart';

/// VERIFY (Task 6.2): the Task 6.1 presentational pending-requests queue is
/// now fed by the REAL [LocalConnectionRequestsBloc] + repository, and the
/// conversation list resolves remembered PUBLIC usernames through the
/// [MemoryUsernameDirectory].
void main() {
  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const hashB =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const myHash =
      'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc';

  Conversation conv(String id, String hash) => Conversation(
        id: id,
        participantHash: hash,
        encryptedSessionState: Uint8List.fromList([1, 2, 3]),
      );

  LocalConnectionRequestRepository newRequests() =>
      LocalConnectionRequestRepository(
        store: InMemoryEntityStore((r) => r.id),
        syncQueue: LocalSyncQueueRepository(
          store: queueStore(),
          cipher: testCipher(),
        ),
      );

  testWidgets(
      'pending-requests queue renders from the real requests BLoC and '
      'accept() removes the request', (tester) async {
    final requests = newRequests();
    await requests.send(requesterHash: hashA, targetHash: myHash);
    final database = LocalDataStreamController<ConnectionRequest>();
    final requestsBloc = LocalConnectionRequestsBloc(
      repository: requests,
      database: database,
      myBlindHash: myHash,
    );

    final repository = FakeConversationRepository();
    final convDatabase = LocalDataStreamController<Conversation>();
    final convBloc =
        LocalConversationBloc(repository: repository, database: convDatabase);

    await tester.pumpWidget(MaterialApp(
      home: VaultConversationListScreen(
        bloc: convBloc,
        requestsBloc: requestsBloc,
      ),
    ));
    await requestsBloc.start();
    await convBloc.start();
    await tester.pump();
    await tester.pump();

    // The inbox tile renders the derived non-PII handle (no username known).
    expect(find.text('PENDING REQUESTS (1)'), findsOneWidget);
    expect(find.text(formatPeerHandle(hashA)), findsOneWidget);
    expect(find.text('Accept'), findsOneWidget);
    // No raw hash anywhere in the tree.
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data ?? '')
        .join('|');
    expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);

    // Accept → the request transitions and leaves the inbox.
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.pump();
    expect(find.text('PENDING REQUESTS (1)'), findsNothing);
    expect(
        (await requests.getById((await requests.getAll()).single.id))!.status,
        ConnectionRequestStatus.accepted);

    // Teardown in the REAL async zone (close futures hang in the fake
    // zone — documented codebase convention, see the 6.1 integration test).
    await tester.runAsync(() async {
      await requestsBloc.close();
      await convBloc.close();
      await database.close();
      await convDatabase.close();
    });
  });

  testWidgets(
      'conversation tiles render remembered PUBLIC usernames via the '
      'directory (fallback = derived handle)', (tester) async {
    final directory = MemoryUsernameDirectory({hashA: 'rekha_k'});
    final repository = FakeConversationRepository()
      ..seed([conv('c1', hashA), conv('c2', hashB)]);
    final convDatabase = LocalDataStreamController<Conversation>();
    final convBloc =
        LocalConversationBloc(repository: repository, database: convDatabase);

    final requestsBloc = LocalConnectionRequestsBloc(
      repository: newRequests(),
      database: LocalDataStreamController<ConnectionRequest>(),
      myBlindHash: myHash,
    );

    await tester.pumpWidget(MaterialApp(
      home: VaultConversationListScreen(
        bloc: convBloc,
        requestsBloc: requestsBloc,
        usernameDirectory: directory,
      ),
    ));
    await requestsBloc.start();
    await convBloc.start();
    await tester.pump();
    await tester.pump();
    await tester.pump();

    // Known peer → @username; unknown peer → derived handle.
    expect(find.text('@rekha_k'), findsOneWidget);
    expect(find.text(formatPeerHandle(hashB)), findsOneWidget);
    expect(find.textContaining(hashA), findsNothing);

    await tester.runAsync(() async {
      await requestsBloc.close();
      await convBloc.close();
      await convDatabase.close();
    });
  });

  testWidgets(
      'late-subscribe: queue renders when the bloc emits before '
      'subscription', (tester) async {
    final requests = newRequests();
    await requests.send(requesterHash: hashA, targetHash: myHash);
    final database = LocalDataStreamController<ConnectionRequest>();
    final requestsBloc = LocalConnectionRequestsBloc(
      repository: requests,
      database: database,
      myBlindHash: myHash,
    );
    final convBloc = _StaticConversationBloc();

    // Emit the requests state BEFORE the widget subscribes (broadcast
    // stream, no replay) — the screen's initState refresh() must pull it.
    await requestsBloc.start();

    await tester.pumpWidget(MaterialApp(
      home: VaultConversationListScreen(
        bloc: convBloc,
        requestsBloc: requestsBloc,
      ),
    ));
    // Start AFTER pumping so the outer StreamBuilder subscribes before the
    // conversation state emits (broadcast, no replay).
    await convBloc.start();
    await tester.pump();
    await tester.pump();

    expect(find.text('PENDING REQUESTS (1)'), findsOneWidget);

    await tester.runAsync(() async {
      await requestsBloc.close();
      await database.close();
      await convBloc.close();
    });
  });
}

/// Scripted conversation bloc that emits one loaded, empty state.
class _StaticConversationBloc implements ConversationBloc {
  final StreamController<ConversationState> _controller =
      StreamController<ConversationState>.broadcast();

  @override
  Stream<ConversationState> get state => _controller.stream;

  @override
  Future<void> start() async {
    await refresh();
  }

  @override
  Future<void> refresh() async {
    _controller.add(const ConversationState(hasLoaded: true));
  }

  @override
  Future<void> close() async {
    await _controller.close();
  }
}
