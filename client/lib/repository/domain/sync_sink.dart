import 'conflict_resolution.dart';
import 'sync_queue_item.dart';

/// The ONLY network boundary in the repository layer (port).
///
/// SECURITY CHECKPOINT (Task 3.2): repositories NEVER make direct HTTP calls.
/// All outbound synchronization flows exclusively through this injected port,
/// whose concrete implementation (built in a later phase) performs the actual
/// transport. Repositories only ever hand this sink opaque, already-encrypted
/// [SyncQueueItem] payloads — the sink can never observe plaintext.
abstract class SyncSink {
  /// Pushes one queued mutation to the remote.
  ///
  /// Returns a [SyncPushOutcome] describing how the remote treated the push
  /// (Task 5.5): acknowledged, retryable-rejected, or CONFLICT — a 409-style
  /// divergence where the remote carries a different [MutationVersion] for
  /// the same entity. The sync loop consults the conflict-resolution policy
  /// on the conflict path; acknowledged/rejected map to success/retry as in
  /// earlier phases.
  Future<SyncPushOutcome> push(SyncQueueItem item);
}

/// How the remote treated a single push (Task 5.5).
///
/// This is a deliberate evolution of the old `Future<bool>` contract: a
/// boolean could only express acknowledged-vs-not, which forced the sync
/// loop to treat a 409 conflict identically to a transient network failure.
/// The three-way outcome lets the worker:
/// - mark acknowledged items success (as before),
/// - retry rejected items with backoff (as before), and
/// - resolve CONFLICTS deterministically via the injected
///   [ConflictResolutionPolicy] — no data loss, no double application.
class SyncPushOutcome {
  final SyncPushStatus status;

  /// The remote's authoritative version when [status] is
  /// [SyncPushStatus.conflict]; null otherwise.
  final MutationVersion? remoteVersion;

  const SyncPushOutcome.acknowledged()
      : status = SyncPushStatus.acknowledged,
        remoteVersion = null;

  const SyncPushOutcome.rejected()
      : status = SyncPushStatus.rejected,
        remoteVersion = null;

  const SyncPushOutcome.conflict(MutationVersion this.remoteVersion)
      : status = SyncPushStatus.conflict;

  bool get isAcknowledged => status == SyncPushStatus.acknowledged;
  bool get isRejected => status == SyncPushStatus.rejected;
  bool get isConflict => status == SyncPushStatus.conflict;
}

/// The three push dispositions a remote can return.
enum SyncPushStatus { acknowledged, rejected, conflict }
