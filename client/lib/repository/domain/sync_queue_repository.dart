import 'dart:typed_data';

import 'base_repository.dart';
import 'sync_queue_item.dart';

/// Repository for pending sync operations (Task 3.2; queue engine in 3.3).
///
/// All mutation operations enqueue a [SyncQueueItem] here before anything
/// leaves the device. The sync layer drains [getPending] and marks outcomes.
///
/// SECURITY CHECKPOINT (Task 3.3): [enqueue] seals the payload with the
/// injected [QueuePayloadCipher] BEFORE storage — the queue never persists
/// plaintext mutation payloads.
abstract class SyncQueueRepository implements BaseRepository<SyncQueueItem> {
  /// The canonical insertion path for every mutation (POST/PUT/DELETE).
  ///
  /// The [payload] is encrypted with the [QueuePayloadCipher] before it is
  /// written to the store; the returned item carries the SEALED payload.
  /// The item starts in the [SyncQueueStatus.pending] state.
  Future<SyncQueueItem> enqueue({
    required SyncOperationType operationType,
    required Uint8List payload,
  });

  /// Every item still awaiting delivery (status == pending), oldest first.
  Future<List<SyncQueueItem>> getPending();

  /// Items currently in the `failed` state whose backoff window has elapsed,
  /// eligible for a retry (Task 5.2).
  ///
  /// An item is retry-eligible when `now >= lastAttemptAt + retryDelay(retryCount)`.
  /// Items with no recorded [SyncQueueItem.lastAttemptAt] are treated as
  /// eligible (never attempted is immediately retryable). The caller supplies
  /// the delay function (typically an [ExponentialBackoff] with jitter), so
  /// the repository stays deterministic and clock-injectable.
  Future<List<SyncQueueItem>> getRetryable({
    required DateTime now,
    required Duration Function(int retryCount) retryDelay,
  });

  /// Marks the item with [id] as currently being processed and stamps its
  /// [SyncQueueItem.lastAttemptAt] with the current time (retry gating).
  Future<void> markInProgress(String id);

  /// Marks the item with [id] as successfully delivered to the remote.
  Future<void> markSuccess(String id);

  /// Marks the item with [id] as failed and increments its retry counter.
  Future<void> markFailed(String id);

  /// Recovers items stranded in the `in_progress` state (Task 5.2).
  ///
  /// If the app is killed mid-drain (crash, battery pull, OS kill), items
  /// left `in_progress` would otherwise never be retried. Calling this at the
  /// START of every sync run resets them to [SyncQueueStatus.pending] so the
  /// drain picks them up again. Idempotent — no-ops when nothing is stranded.
  ///
  /// SECURITY CHECKPOINT (Task 5.2): recovery only flips the status column;
  /// sealed payloads are untouched and never re-encrypted.
  Future<void> recoverInterrupted();

  /// Deletes queue items older than [maxAge] (Task 5.6 — 30-day retention).
  ///
  /// A mutation that has sat unsynced past the retention window is stale —
  /// the server's own 30-day offline-queue TTL mirrors this boundary, so a
  /// retry would be rejected as expired anyway. Expired items are purged
  /// regardless of status (pending/failed/in_progress leftovers included).
  ///
  /// [now] is clock-injectable for deterministic tests. Returns the number
  /// of items purged. Idempotent — no-ops when nothing has expired.
  ///
  /// SECURITY CHECKPOINT (Task 5.6): purging deletes only the sealed rows;
  /// sealed payloads are never opened, decrypted, or logged.
  Future<int> purgeExpired({
    DateTime? now,
    Duration maxAge = const Duration(days: 30),
  });
}
