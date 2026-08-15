import 'package:civic_commons/repository/data/local_connection_request_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/memory_user_search_repository.dart';
import 'package:civic_commons/repository/domain/connection_request.dart';
import 'package:civic_commons/security/domain/secure_flag_service.dart';
import 'package:civic_commons/state/data/local_connection_requests_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/data/local_user_search_bloc.dart';
import 'package:civic_commons/state/ui/username_search_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../repository/fakes.dart';

/// VERIFY (Task 6.2): the username search sheet drives the search BLoC,
/// renders the found PUBLIC username (never the raw blind hash, never a
/// phone), wires the send-request action through the requests BLoC, and is
/// wrapped in FLAG_SECURE.
void main() {
  const hashA =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
  const myHash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

  group('UsernameSearchSheet - search flow', () {
    late MemoryUserSearchRepository search;
    late LocalUserSearchBloc searchBloc;
    late LocalConnectionRequestRepository requests;
    late LocalDataStreamController<ConnectionRequest> database;
    late LocalConnectionRequestsBloc requestsBloc;

    setUp(() {
      search = MemoryUserSearchRepository();
      searchBloc = LocalUserSearchBloc(repository: search);
      requests = LocalConnectionRequestRepository(
        store: InMemoryEntityStore((r) => r.id),
        syncQueue: LocalSyncQueueRepository(
          store: queueStore(),
          cipher: testCipher(),
        ),
      );
      database = LocalDataStreamController<ConnectionRequest>();
      requestsBloc = LocalConnectionRequestsBloc(
        repository: requests,
        database: database,
        myBlindHash: myHash,
      );
    });

    tearDown(() async {
      await searchBloc.close();
      await requestsBloc.close();
      await database.close();
    });

    Future<void> pumpSheet(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UsernameSearchSheet(
            searchBloc: searchBloc,
            requestsBloc: requestsBloc,
          ),
        ),
      ));
      await tester.pump();
    }

    testWidgets('searching a known username renders the found result',
        (tester) async {
      search.seed('rekha_k', hashA);
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField), 'rekha_k');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      await tester.pump();

      // The PUBLIC username is the identifier shown.
      expect(find.text('@rekha_k'), findsOneWidget);
      // The raw blind hash never renders.
      expect(find.textContaining(hashA), findsNothing);
      // The send action is available.
      expect(find.text('Send connection request'), findsOneWidget);
    });

    testWidgets('unknown username renders the not-found message',
        (tester) async {
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField), 'nobody_here_99');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      await tester.pump();

      expect(find.text('No user found with that username.'), findsOneWidget);
      expect(find.text('Send connection request'), findsNothing);
    });

    testWidgets(
        'send request creates the outgoing request via the requests '
        'bloc and shows confirmation', (tester) async {
      search.seed('rekha_k', hashA);
      await pumpSheet(tester);

      await tester.enterText(find.byType(TextField), 'rekha_k');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      await tester.pump();

      await tester.tap(find.text('Send connection request'));
      await tester.pump();
      await tester.pump();

      expect(find.text('Connection request sent'), findsOneWidget);

      final stored = await requests.getAll();
      expect(stored, hasLength(1));
      expect(stored.single.requesterHash, myHash);
      expect(stored.single.recipientHash, hashA);
    });
  });

  group('UsernameSearchSheet - FLAG_SECURE + PII scans (Task 6.2)', () {
    testWidgets('enables FLAG_SECURE on mount', (tester) async {
      final flag = _RecordingFlagService();
      final searchBloc =
          LocalUserSearchBloc(repository: MemoryUserSearchRepository());
      final requestsBloc = LocalConnectionRequestsBloc(
        repository: LocalConnectionRequestRepository(
          store: InMemoryEntityStore((r) => r.id),
          syncQueue: LocalSyncQueueRepository(
            store: queueStore(),
            cipher: testCipher(),
          ),
        ),
        database: LocalDataStreamController<ConnectionRequest>(),
        myBlindHash: myHash,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UsernameSearchSheet(
            searchBloc: searchBloc,
            requestsBloc: requestsBloc,
            secureFlagService: flag,
          ),
        ),
      ));
      await tester.pump();

      expect(flag.enableCalls, 1);

      await searchBloc.close();
      await requestsBloc.close();
    });

    testWidgets('the found-result tree renders no PII-shaped text',
        (tester) async {
      final searchBloc = LocalUserSearchBloc(
        repository: MemoryUserSearchRepository()..seed('rekha_k', hashA),
      );
      final requestsBloc = LocalConnectionRequestsBloc(
        repository: LocalConnectionRequestRepository(
          store: InMemoryEntityStore((r) => r.id),
          syncQueue: LocalSyncQueueRepository(
            store: queueStore(),
            cipher: testCipher(),
          ),
        ),
        database: LocalDataStreamController<ConnectionRequest>(),
        myBlindHash: myHash,
      );

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: UsernameSearchSheet(
            searchBloc: searchBloc,
            requestsBloc: requestsBloc,
          ),
        ),
      ));
      await tester.enterText(find.byType(TextField), 'rekha_k');
      await tester.tap(find.widgetWithText(FilledButton, 'Search'));
      await tester.pump();
      await tester.pump();

      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .join('|');
      expect(texts, isNot(contains('+91')));
      expect(texts, isNot(contains('hvs.')));
      // No full 64-hex blind hash in the tree.
      expect(RegExp(r'\b[0-9a-f]{64}\b').hasMatch(texts), isFalse);
      // The username is the public identifier — the hash is not.
      expect(texts, contains('@rekha_k'));

      await searchBloc.close();
      await requestsBloc.close();
    });
  });
}

class _RecordingFlagService implements SecureFlagService {
  int enableCalls = 0;

  @override
  Future<void> disableSecureFlag() async {}

  @override
  Future<void> enableSecureFlag() async {
    enableCalls++;
  }

  @override
  Future<bool> isSecureFlagSupported() async => true;
}
