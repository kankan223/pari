import 'dart:convert';
import 'dart:typed_data';

import '../domain/connection_request.dart';
import '../domain/connection_request_repository.dart';
import '../domain/entity_store.dart';
import '../domain/idempotency_key.dart';
import '../domain/sync_queue_item.dart';
import '../domain/sync_queue_repository.dart';

/// Local-first [ConnectionRequestRepository] for the Vault (data layer,
/// Task 6.2).
///
/// Same offline-first contract as [LocalConversationRepository]:
/// mutations (send/accept/reject/withdraw) persist to the encrypted local
/// store immediately, then enqueue a [SyncQueueItem]; reads serve the local
/// snapshot with zero network I/O; the injected [SyncSink] transports the
/// queued envelopes on the next sync run.
///
/// SECURITY CHECKPOINT (Task 6.2):
/// - The repository NEVER sees a phone number. [send] requires a target that
///   is a 64-hex blind hash; anything else is rejected before it can reach
///   storage or the queue (a raw phone can never be persisted or synced).
/// - Queued envelopes carry only blind hashes + status; the queue cipher
///   additionally seals them at rest (Task 3.3).
/// - Single-transition state machine: only `pending` requests may transition
///   (mirrors the relay's CAS rule); terminal states are immutable.
class LocalConnectionRequestRepository implements ConnectionRequestRepository {
  final EntityStore<ConnectionRequest> _store;
  final SyncQueueRepository _syncQueue;
  final IdempotencyKeyGenerator _idGen;

  LocalConnectionRequestRepository({
    required EntityStore<ConnectionRequest> store,
    required SyncQueueRepository syncQueue,
    IdempotencyKeyGenerator? idempotencyKeys,
  })  : _store = store,
        _syncQueue = syncQueue,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator();

  @override
  Future<ConnectionRequest> create(ConnectionRequest entity) async {
    await _store.insert(entity);
    return entity;
  }

  @override
  Future<ConnectionRequest?> getById(String id) => _store.getById(id);

  @override
  Future<List<ConnectionRequest>> getAll() => _store.getAll();

  @override
  Future<ConnectionRequest> update(ConnectionRequest entity) async {
    await _store.update(entity);
    return entity;
  }

  @override
  Future<void> delete(String id) => _store.delete(id);

  @override
  Future<List<ConnectionRequest>> listIncomingPending(
      String recipientHash) async {
    final all = await _store.getAll();
    return all
        .where((r) =>
            r.recipientHash == recipientHash &&
            r.status == ConnectionRequestStatus.pending)
        .toList(growable: false);
  }

  @override
  Future<ConnectionRequest?> findPendingPair(
      String requesterHash, String recipientHash) async {
    final all = await _store.getAll();
    for (final r in all) {
      if (r.status == ConnectionRequestStatus.pending &&
          r.requesterHash == requesterHash &&
          r.recipientHash == recipientHash) {
        return r;
      }
    }
    return null;
  }

  @override
  Future<ConnectionRequest> send({
    required String requesterHash,
    required String targetHash,
  }) async {
    // SECURITY CHECKPOINT: only a 64-hex blind hash may be a target — this
    // is the boundary that guarantees a raw phone number can never enter
    // storage or the sync queue.
    if (!isBlindHashId(targetHash)) {
      throw ArgumentError.value(
          targetHash, 'targetHash', 'must be a 64-hex blind hash id');
    }
    if (!isBlindHashId(requesterHash)) {
      throw ArgumentError.value(
          requesterHash, 'requesterHash', 'must be a 64-hex blind hash id');
    }
    // Idempotent while pending (mirrors the relay's request-spam prevention).
    final existing = await findPendingPair(requesterHash, targetHash);
    if (existing != null) {
      return existing;
    }
    final request = ConnectionRequest(
      id: _idGen.generate(),
      requesterHash: requesterHash,
      recipientHash: targetHash,
      status: ConnectionRequestStatus.pending,
    );
    await _store.insert(request);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.create,
      payload: _envelope('send', request),
    );
    return request;
  }

  @override
  Future<ConnectionRequest> accept(String id) =>
      _transition(id, ConnectionRequestStatus.accepted);

  @override
  Future<ConnectionRequest> reject(String id) =>
      _transition(id, ConnectionRequestStatus.rejected);

  @override
  Future<ConnectionRequest> withdraw(String id) =>
      _transition(id, ConnectionRequestStatus.withdrawn);

  /// Single-transition state machine: only `pending` requests may move, and
  /// terminal states are immutable (mirrors the relay's CAS enforcement).
  Future<ConnectionRequest> _transition(
      String id, ConnectionRequestStatus to) async {
    final existing = await _store.getById(id);
    if (existing == null) {
      throw StateError('Connection request not found: $id');
    }
    if (existing.status.isTerminal) {
      throw StateError(
          'Connection request no longer pending: $id (${existing.status.wireName})');
    }
    final updated = existing.copyWith(status: to);
    await _store.update(updated);
    await _syncQueue.enqueue(
      operationType: SyncOperationType.update,
      payload: _envelope(to.wireName, updated),
    );
    return updated;
  }

  /// Serializes a mutation envelope for the sync queue. Contains ONLY blind
  /// hashes and status — no phone numbers, no usernames, no message bodies.
  /// The queue cipher additionally seals the envelope at rest.
  Uint8List _envelope(String action, ConnectionRequest request) =>
      Uint8List.fromList(utf8.encode(jsonEncode({
        'action': action,
        'id': request.id,
        'requester_hash': request.requesterHash,
        'recipient_hash': request.recipientHash,
        'status': request.status.wireName,
      })));
}

/// Whether [value] looks like a 64-hex-character blind hash id.
bool isBlindHashId(String value) {
  if (value.length != 64) {
    return false;
  }
  for (final code in value.codeUnits) {
    final isDigit = code >= 0x30 && code <= 0x39;
    final isLower = code >= 0x61 && code <= 0x66;
    if (!isDigit && !isLower) {
      return false;
    }
  }
  return true;
}
