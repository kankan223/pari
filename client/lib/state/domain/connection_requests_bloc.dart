import 'connection_requests_state.dart';

/// BLoC for the Vault pending-requests inbox (Task 6.2).
///
/// Exposes a stream of [ConnectionRequestsState] derived from the local
/// connection_requests store. The UI binds to [state] and never talks to
/// the repository or network directly (clean architecture, offline-first).
///
/// SECURITY CHECKPOINT (Task 6.2): [ConnectionRequestsState] carries only
/// UI-safe [PendingRequestSummary]s — request ids, blind hashes, and any
/// request metadata are never rendered raw; peers are addressed through
/// [formatPeerHandle] or a remembered public username.
abstract class ConnectionRequestsBloc {
  /// Stream of inbox states (initial + every store change).
  Stream<ConnectionRequestsState> get state;

  /// Starts listening to the local store stream and emits the current
  /// snapshot. Must be called once before reading [state].
  Future<void> start();

  /// Re-reads the local store and emits a fresh snapshot.
  Future<void> refresh();

  /// Accepts the pending request with [id] (approval). Local-first: the
  /// mutation persists + enqueues for sync, then the inbox refreshes.
  Future<void> accept(String id);

  /// Rejects the pending request with [id] (refusal). Local-first, then
  /// refresh.
  Future<void> reject(String id);

  /// Sends a connection request to [targetHash] (a 64-hex blind hash) on
  /// behalf of the current user. Local-first: persists + enqueues, then
  /// refreshes the inbox (the new outgoing request is not in the inbox, but
  /// any in-flight state stays consistent).
  Future<void> sendRequest(String targetHash);

  /// Releases resources.
  Future<void> close();
}
