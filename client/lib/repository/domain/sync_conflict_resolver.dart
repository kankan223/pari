import 'conflict_resolution.dart';
import 'sync_queue_item.dart';
import 'sync_sink.dart';

/// What the sync loop should do with a queued item after a push (Task 5.5).
enum SyncDisposition {
  /// The remote acknowledged the push — mark the item success.
  success,

  /// The push was rejected (transient) or the CONFLICT resolved in the
  /// LOCAL version's favour — keep the item, retry with backoff.
  retry,

  /// The CONFLICT resolved in the REMOTE version's favour — the local
  /// mutation is superseded: drop the item from the queue; the entity state
  /// will converge from the remote on the next pull.
  superseded,
}

/// The sync loop's decision for one push, produced by [SyncConflictResolver].
class SyncResolution {
  final SyncDisposition disposition;

  /// The underlying policy outcome (null when the push was not a conflict).
  final ConflictResolution? resolution;

  const SyncResolution(this.disposition, {this.resolution});

  bool get isSuccess => disposition == SyncDisposition.success;
  bool get isRetry => disposition == SyncDisposition.retry;
  bool get isSuperseded => disposition == SyncDisposition.superseded;
}

/// Wires the conflict-resolution policy into the sync push loop (Task 5.5).
///
/// Lives in the REPOSITORY domain (not the sync layer) because it decides the
/// fate of queued repository items — the sync worker and the local-first
/// repositories both depend on it, keeping the dependency direction
/// repository → (worker builds on repository), never the reverse.
///
/// This is the deterministic bridge between the [SyncSink]'s three-way push
/// outcome and the queue state machine:
/// - **acknowledged** → [SyncDisposition.success] (unchanged from 5.2).
/// - **rejected** → [SyncDisposition.retry] (unchanged from 5.2).
/// - **conflict** → build the LOCAL [MutationVersion] for the item and run it
///   through the injected [ConflictResolutionPolicy] against the remote
///   version returned by the sink. applyLocal → retry (the local edit is
///   re-submitted); applyRemote → superseded (the remote is authoritative);
///   merge → superseded at queue level (the merged aggregate is recorded on
///   the resolution; entity state converges on the next pull, since the
///   opaque queued payload cannot carry the merged value itself).
///
/// Determinism contract: the SAME policy used on every device + the same
/// local version inputs → the same disposition everywhere. No split-brain.
///
/// SECURITY CHECKPOINT (Task 5.5): the resolver operates ONLY on blind-hash
/// IDs, UUIDs, and timestamps — never on payload contents. Queue payloads
/// are opaque sealed ciphertext and are never opened, merged, or logged here.
class SyncConflictResolver {
  final ConflictResolutionPolicy _policy;

  /// The local actor's blind-hash ID, used as the [MutationVersion.authorHash]
  /// tiebreak discriminator. Never PII — a 64-hex blind hash.
  final String actorHash;

  const SyncConflictResolver({
    ConflictResolutionPolicy policy = const ServerAuthoritativeLastWriteWins(),
    this.actorHash = 'local-device',
  }) : _policy = policy;

  /// Decides the [SyncDisposition] for [item] after [outcome].
  ///
  /// [localVersion] optionally overrides the local [MutationVersion] built
  /// from the queue item — the entity layer passes a version carrying the
  /// local aggregate [MutationVersion.value] so mergeable conflicts (e.g.
  /// karma scores) reach the [MergePolicy] instead of degrading to LWW.
  /// When omitted, the local version carries no aggregate value (the opaque
  /// queued payload cannot expose one) and LWW applies.
  SyncResolution resolve({
    required SyncQueueItem item,
    required SyncPushOutcome outcome,
    MutationVersion? localVersion,
  }) {
    switch (outcome.status) {
      case SyncPushStatus.acknowledged:
        return const SyncResolution(SyncDisposition.success);

      case SyncPushStatus.rejected:
        return const SyncResolution(SyncDisposition.retry);

      case SyncPushStatus.conflict:
        final remote = outcome.remoteVersion!;
        final local = localVersion ??
            MutationVersion(
              entityId: item.id,
              timestamp: item.createdAt,
              serverAcknowledged: false,
              authorHash: actorHash,
            );
        final resolved = _policy.resolve(local: local, remote: remote);
        switch (resolved.decision) {
          case ConflictDecision.applyLocal:
            // Local edit wins: keep the item so it is re-submitted.
            return SyncResolution(SyncDisposition.retry, resolution: resolved);

          case ConflictDecision.applyRemote:
            // Remote is authoritative: the local mutation is superseded.
            return SyncResolution(SyncDisposition.superseded,
                resolution: resolved);

          case ConflictDecision.merge:
            // The aggregate merge is recorded on the resolution; the entity
            // layer persists the merged value and the opaque queued payload
            // (which cannot carry it) is superseded.
            return SyncResolution(SyncDisposition.superseded,
                resolution: resolved);
        }
    }
  }
}
