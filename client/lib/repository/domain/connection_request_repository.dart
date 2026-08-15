import 'base_repository.dart';
import 'connection_request.dart';

/// Repository for Vault connection requests (Task 6.2).
///
/// Extends the standard CRUD contract with the request-flow operations.
/// All data is read/written through the encrypted local store; outbound
/// mutations (send/accept/reject/withdraw) flow through the injected
/// [SyncSink] as queued [SyncQueueItem]s (offline-first — the UI returns
/// immediately after the local write, the gateway sync happens in the
/// background).
///
/// SECURITY CHECKPOINT (Task 6.2): the repository operates ONLY on
/// blind_hash_ids — it never sees, stores, or transports a phone number.
/// The target of every [send] is validated to be a 64-hex blind hash.
abstract class ConnectionRequestRepository
    implements BaseRepository<ConnectionRequest> {
  /// Lists requests where [recipientHash] is the target AND the request is
  /// still [ConnectionRequestStatus.pending] — the Vault inbox.
  Future<List<ConnectionRequest>> listIncomingPending(String recipientHash);

  /// Returns the pending request between [requesterHash] and
  /// [recipientHash], or null when none exists.
  Future<ConnectionRequest?> findPendingPair(
      String requesterHash, String recipientHash);

  /// Sends a connection request from [requesterHash] to [targetHash]
  /// (a 64-hex blind hash). Local-first: persists immediately, enqueues the
  /// mutation, and returns the created request. Idempotent while pending —
  /// a second send for the same pair returns the existing request (mirrors
  /// the relay's request-spam prevention).
  Future<ConnectionRequest> send({
    required String requesterHash,
    required String targetHash,
  });

  /// Accepts the pending request with [id] (recipient-side approval).
  /// Throws [StateError] if the request is not pending.
  Future<ConnectionRequest> accept(String id);

  /// Rejects the pending request with [id] (recipient-side refusal).
  /// Throws [StateError] if the request is not pending.
  Future<ConnectionRequest> reject(String id);

  /// Withdraws the pending request with [id] (initiator-side cancel).
  /// Throws [StateError] if the request is not pending.
  Future<ConnectionRequest> withdraw(String id);
}
