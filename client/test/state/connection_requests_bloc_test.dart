import 'package:civic_commons/repository/data/local_connection_request_repository.dart';
import 'package:civic_commons/repository/data/local_sync_queue_repository.dart';
import 'package:civic_commons/repository/data/memory_username_directory.dart';
import 'dart:async';

import 'package:civic_commons/repository/domain/connection_request.dart';
import 'package:civic_commons/repository/domain/username_directory.dart';
import 'package:civic_commons/state/data/local_connection_requests_bloc.dart';
import 'package:civic_commons/state/data/local_data_stream_controller.dart';
import 'package:civic_commons/state/domain/connection_requests_state.dart';
import 'package:civic_commons/state/domain/pending_request_summary.dart';
import 'package:civic_commons/state/domain/session_establisher.dart';
import 'package:flutter_test/flutter_test.dart';

import '../repository/fakes.dart';

/// VERIFY (Task 6.2): LocalConnectionRequestsBloc projects the local
/// connection_requests store into the UI-safe inbox (pending requests
/// targeting the current user), resolves remembered usernames, and wires
/// accept/reject/send through the repository.
void main() {
  const myHash =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  const requester =
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

  LocalConnectionRequestRepository newRepository() =>
      LocalConnectionRequestRepository(
        store: InMemoryEntityStore((r) => r.id),
        syncQueue: LocalSyncQueueRepository(
          store: queueStore(),
          cipher: testCipher(),
        ),
      );

  group('LocalConnectionRequestsBloc - inbox projection', () {
    late LocalConnectionRequestRepository repository;
    late LocalDataStreamController<ConnectionRequest> database;
    late LocalConnectionRequestsBloc bloc;
    late List<ConnectionRequestsState> states;

    setUp(() {
      repository = newRepository();
      database = LocalDataStreamController<ConnectionRequest>();
      bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
      );
      states = [];
      bloc.state.listen(states.add);
    });

    tearDown(() async {
      await bloc.close();
      await database.close();
    });

    test('start() emits hasLoaded=true with the pending inbox', () async {
      await repository.send(requesterHash: requester, targetHash: myHash);
      await bloc.start();
      await flushMicrotasks();

      expect(states, isNotEmpty);
      expect(states.last.hasLoaded, isTrue);
      expect(states.last.pending, hasLength(1));
      expect(states.last.pending.single.requesterHash, requester);
    });

    test('only requests targeting me + pending appear in the inbox', () async {
      await repository.send(requesterHash: requester, targetHash: myHash);
      await repository.send(requesterHash: myHash, targetHash: requester);
      await bloc.start();
      await flushMicrotasks();

      // The outgoing request (I am the requester) is not in my inbox.
      expect(states.last.pending, hasLength(1));
    });

    test('database stream emission triggers a fresh inbox projection',
        () async {
      await bloc.start();
      await flushMicrotasks();

      await repository.send(requesterHash: requester, targetHash: myHash);
      database.emit(await repository.getAll());
      await flushMicrotasks();

      expect(states.last.pending, hasLength(1));
    });

    test('accept() transitions via the repository and refreshes', () async {
      final request =
          await repository.send(requesterHash: requester, targetHash: myHash);
      await bloc.start();
      await flushMicrotasks();
      expect(states.last.pending, hasLength(1));

      await bloc.accept(request.id);
      await flushMicrotasks();

      expect(states.last.pending, isEmpty);
      final stored = await repository.getById(request.id);
      expect(stored!.status, ConnectionRequestStatus.accepted);
    });

    test('sendRequest() enqueues an outgoing request for the target hash',
        () async {
      await bloc.start();
      await flushMicrotasks();

      await bloc.sendRequest(requester);

      final stored = await repository.getAll();
      expect(stored, hasLength(1));
      expect(stored.single.requesterHash, myHash);
      expect(stored.single.recipientHash, requester);
    });
  });

  group('LocalConnectionRequestsBloc - username resolution (Task 6.2)', () {
    test('remembered requester username rides on the summary', () async {
      final directory = MemoryUsernameDirectory();
      await directory.remember(username: 'rekha_k', blindHashId: requester);

      final repository = newRepository();
      await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        directory: directory,
      );

      final states = <ConnectionRequestsState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      await flushMicrotasks();

      final summary = states.last.pending.single;
      expect(summary, isA<PendingRequestSummary>());
      expect(summary.requesterUsername, 'rekha_k');
      expect(summary.requesterHash, requester);

      await bloc.close();
      await database.close();
    });

    test('unknown requester keeps the derived handle (username null)',
        () async {
      final repository = newRepository();
      await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        directory: MemoryUsernameDirectory(),
      );

      final states = <ConnectionRequestsState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      await flushMicrotasks();

      expect(states.last.pending.single.requesterUsername, isNull);

      await bloc.close();
      await database.close();
    });

    test('a throwing directory lookup degrades to the derived handle',
        () async {
      final repository = newRepository();
      await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        directory: _ThrowingDirectory(),
      );

      final states = <ConnectionRequestsState>[];
      bloc.state.listen(states.add);
      await bloc.start();
      await flushMicrotasks();

      // The inbox still renders — username falls back to null (derived
      // non-PII handle) instead of crashing the stream.
      expect(states.last.hasLoaded, isTrue);
      expect(states.last.pending.single.requesterUsername, isNull);

      await bloc.close();
      await database.close();
    });
  });

  group('LocalConnectionRequestsBloc - approval key-exchange hook (Task 6.3)',
      () {
    test('accept() establishes a session with the requester (blind hash)',
        () async {
      final establisher = _RecordingEstablisher();
      final repository = newRepository();
      final request =
          await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        sessionEstablisher: establisher,
      );

      await bloc.accept(request.id);
      await flushMicrotasks();

      // The hook fires with the requester's blind hash — never a phone or
      // username.
      expect(establisher.calls, [requester]);

      await bloc.close();
      await database.close();
    });

    test('accept() without an establisher still succeeds (no-op)', () async {
      final repository = newRepository();
      final request =
          await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
      );

      await bloc.accept(request.id);
      await flushMicrotasks();

      final stored = await repository.getById(request.id);
      expect(stored!.status, ConnectionRequestStatus.accepted);

      await bloc.close();
      await database.close();
    });

    test('a failing establisher never fails the local accept', () async {
      final repository = newRepository();
      final request =
          await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        sessionEstablisher: _ThrowingEstablisher(),
      );

      await bloc.accept(request.id);
      await flushMicrotasks();

      // The request is accepted locally even though establishment failed —
      // a later sync run can retry establishment.
      final stored = await repository.getById(request.id);
      expect(stored!.status, ConnectionRequestStatus.accepted);

      await bloc.close();
      await database.close();
    });
  });

  group('LocalConnectionRequestsBloc - stale-snapshot guard (post-review)', () {
    test('a stale refresh() pull can never overwrite a fresher push', () async {
      final hang = _HangOnceDirectory();
      final repository = newRepository();
      await repository.send(requesterHash: requester, targetHash: myHash);
      final database = LocalDataStreamController<ConnectionRequest>();
      final bloc = LocalConnectionRequestsBloc(
        repository: repository,
        database: database,
        myBlindHash: myHash,
        directory: hang,
      );

      final states = <ConnectionRequestsState>[];
      bloc.state.listen(states.add);

      // start() → refresh() → _emit(seq 1) hangs inside the directory lookup.
      final started = bloc.start();
      await flushMicrotasks();

      // The database pushes a NEWER (empty) snapshot → _emit(seq 2) lands.
      database.emit([]);
      await flushMicrotasks();
      expect(states.last.pending, isEmpty);

      // Release the stale lookup: seq 1 resumes but must be DROPPED.
      hang.release();
      await flushMicrotasks();
      await started;

      expect(states.last.pending, isEmpty,
          reason: 'a stale pull must never resurrect old inbox entries');

      await bloc.close();
      await database.close();
    });
  });
}

/// [UsernameDirectory] whose FIRST lookup hangs until [release] — used to
/// force a refresh() computation to stay in flight across a database push.
class _HangOnceDirectory implements UsernameDirectory {
  final Completer<String?> _first = Completer<String?>();
  bool _hung = false;

  @override
  Future<String?> usernameForHash(String blindHashId) {
    if (!_hung) {
      _hung = true;
      return _first.future;
    }
    return Future<String?>.value(null);
  }

  void release() => _first.complete(null);

  @override
  Future<void> remember({
    required String username,
    required String blindHashId,
  }) async {}
}

/// Records every [SessionEstablisher.establishWith] call.
class _RecordingEstablisher implements SessionEstablisher {
  final List<String> calls = [];

  @override
  Future<void> establishWith(String peerBlindHash) async {
    calls.add(peerBlindHash);
  }
}

/// [SessionEstablisher] that always throws (e.g. bundle unavailable).
class _ThrowingEstablisher implements SessionEstablisher {
  @override
  Future<void> establishWith(String peerBlindHash) async {
    throw StateError('no bundle');
  }
}

/// [UsernameDirectory] whose lookups always throw (storage outage).
class _ThrowingDirectory implements UsernameDirectory {
  @override
  Future<String?> usernameForHash(String blindHashId) async {
    throw StateError('directory unavailable');
  }

  @override
  Future<void> remember({
    required String username,
    required String blindHashId,
  }) async {}
}

/// Flushes pending microtasks so broadcast-stream deliveries land.
Future<void> flushMicrotasks() async {
  for (var i = 0; i < 3; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
