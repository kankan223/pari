import 'dart:async';

import '../../repository/domain/connection_request.dart';
import '../../repository/domain/connection_request_repository.dart';
import '../../repository/domain/username_directory.dart';
import '../domain/connection_requests_bloc.dart';
import '../domain/connection_requests_state.dart';
import '../domain/local_data_stream.dart';
import '../domain/pending_request_summary.dart';
import '../domain/session_establisher.dart';

/// Local-database-backed [ConnectionRequestsBloc] (data layer, Task 6.2).
///
/// Subscribes to the [LocalDataStream] of connection requests and maps each
/// snapshot to a UI-safe [ConnectionRequestsState] of inbox summaries
/// (requests targeting [myBlindHash] that are still pending). Never touches
/// the network — the repository + stream are the only collaborators.
class LocalConnectionRequestsBloc implements ConnectionRequestsBloc {
  final ConnectionRequestRepository _repository;
  final LocalDataStream<ConnectionRequest> _database;
  final UsernameDirectory? _directory;
  final String _myBlindHash;

  /// Task 6.3: the connection-approval key-exchange hook (deferred from
  /// Task 6.2). When non-null, accepting a request also establishes an X3DH
  /// session with the requester so the new connection is ready for
  /// encrypted messaging.
  final SessionEstablisher? _sessionEstablisher;
  final StreamController<ConnectionRequestsState> _controller =
      StreamController<ConnectionRequestsState>.broadcast();
  StreamSubscription<List<ConnectionRequest>>? _sub;

  /// Monotonic snapshot sequence. `refresh()` (pull) and the database-stream
  /// listener (push) can run [_emit] concurrently; the sequence guarantees a
  /// stale computation can never overwrite a newer snapshot (post-review
  /// hardening, Task 6.2).
  int _seq = 0;

  LocalConnectionRequestsBloc({
    required ConnectionRequestRepository repository,
    required LocalDataStream<ConnectionRequest> database,
    required String myBlindHash,
    UsernameDirectory? directory,
    SessionEstablisher? sessionEstablisher,
  })  : _repository = repository,
        _database = database,
        _myBlindHash = myBlindHash,
        _directory = directory,
        _sessionEstablisher = sessionEstablisher;

  @override
  Stream<ConnectionRequestsState> get state => _controller.stream;

  @override
  Future<void> start() async {
    if (_sub != null) {
      return;
    }
    _sub = _database.changes.listen((snapshots) {
      unawaited(_emit(snapshots));
    });
    await refresh();
  }

  @override
  Future<void> refresh() async {
    await _emit(await _repository.getAll());
  }

  @override
  Future<void> accept(String id) async {
    final accepted = await _repository.accept(id);
    // Task 6.3 key-exchange hook: after the local accept is persisted, best-
    // effort X3DH establishment with the requester. A missing bundle (or a
    // transient failure) must NOT fail the accept — the request is already
    // committed locally, and a later sync run can retry establishment.
    final establisher = _sessionEstablisher;
    if (establisher != null) {
      try {
        await establisher.establishWith(accepted.requesterHash);
      } catch (_) {
        // Swallow: session establishment is opportunistic. Never propagate
        // raw bundle/error detail toward the UI.
      }
    }
    await refresh();
  }

  @override
  Future<void> reject(String id) async {
    await _repository.reject(id);
    await refresh();
  }

  @override
  Future<void> sendRequest(String targetHash) async {
    await _repository.send(requesterHash: _myBlindHash, targetHash: targetHash);
  }

  @override
  Future<void> close() async {
    await _sub?.cancel();
    await _controller.close();
  }

  Future<void> _emit(List<ConnectionRequest> requests) async {
    final seq = ++_seq;
    final incoming =
        ConnectionRequestsState.incomingPending(requests, _myBlindHash);
    final directory = _directory;
    final summaries = <PendingRequestSummary>[];
    for (final request in incoming) {
      String? username;
      if (directory != null) {
        try {
          username = await directory.usernameForHash(request.requesterHash);
        } catch (_) {
          // A directory lookup must never crash the inbox — fall back to the
          // derived non-PII handle (username is a display nicety only).
          username = null;
        }
      }
      summaries.add(PendingRequestSummary(
        id: request.id,
        requesterHash: request.requesterHash,
        requesterUsername: username,
      ));
    }
    if (seq != _seq) {
      // A newer snapshot landed while this one computed — drop the stale
      // state so an older pull can never overwrite a fresher push.
      return;
    }
    _controller.add(
      ConnectionRequestsState(pending: summaries, hasLoaded: true),
    );
  }
}
