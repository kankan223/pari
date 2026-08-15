import 'dart:typed_data';

/// Lifecycle status of a queued sync operation (Task 3.2; engine in 3.3).
enum SyncQueueStatus { pending, inProgress, success, failed }

/// The mutation kind a queued item represents (mapped to POST/PUT/DELETE
/// transport semantics in the data layer).
enum SyncOperationType { create, update, delete }

/// A single pending sync operation (domain entity, Task 3.2; retry metadata
/// in Task 5.2).
///
/// Mirrors the `sync_queue` table in `AppSchema`:
/// - [payload] is the opaque, already-encrypted mutation payload (message
///   ciphertext, session state, or an id envelope) — NEVER plaintext.
/// - [retryCount] feeds the exponential backoff logic (Task 3.3); [lastAttemptAt]
///   records when the last push attempt began, so retries are gated by the
///   backoff schedule instead of hammering on every reconnection (Task 5.2).
class SyncQueueItem {
  final String id;
  final SyncOperationType operationType;

  /// Opaque encrypted payload to be transported to the remote.
  final Uint8List payload;

  final SyncQueueStatus status;
  final int retryCount;
  final DateTime createdAt;

  /// When the most recent push attempt began (null = never attempted).
  /// Persisted so retry eligibility survives app restarts.
  final DateTime? lastAttemptAt;

  const SyncQueueItem({
    required this.id,
    required this.operationType,
    required this.payload,
    this.status = SyncQueueStatus.pending,
    this.retryCount = 0,
    required this.createdAt,
    this.lastAttemptAt,
  });
  SyncQueueItem copyWith({
    SyncQueueStatus? status,
    int? retryCount,
    DateTime? lastAttemptAt,
  }) =>
      SyncQueueItem(
        id: id,
        operationType: operationType,
        payload: payload,
        status: status ?? this.status,
        retryCount: retryCount ?? this.retryCount,
        createdAt: createdAt,
        lastAttemptAt: lastAttemptAt ?? this.lastAttemptAt,
      );
}
