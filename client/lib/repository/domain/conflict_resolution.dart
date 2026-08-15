/// Deterministic conflict-resolution hooks for the sync engine (Task 5.2;
/// merge policies + sync-loop wiring in Task 5.5).
///
/// When the local encrypted queue and the remote backend (NATS JetStream /
/// PostgreSQL) diverge, the engine consults a [ConflictResolutionPolicy] to
/// decide which version wins. The default policy is server-authoritative
/// last-write-wins: a version acknowledged by the server beats a local-only
/// version, and otherwise the newer write wins with a deterministic tiebreak
/// so every device converges on the SAME winner (no split-brain).
///
/// Task 5.5 additions:
/// - [MutationVersion.value] — an optional numeric aggregate (e.g. a karma
///   score) that can be MERGED instead of won/lost. Karma is a nested
///   structure: two devices may both vote and both increments matter.
/// - [MergePolicy] (with [MaxMergePolicy]) — deterministic, commutative and
///   idempotent merges for aggregate fields, so replicas converge on the
///   same merged value without double-counting.
/// - [MergeAwareLastWriteWins] — a composite policy that merges aggregate
///   values when both sides carry them and falls back to plain LWW for
///   everything else.
/// - [ConflictDecision.merge] — the outcome when a merge was applied.
///
/// These are pure domain hooks — no I/O, fully unit-testable. The
/// [SyncConflictResolver] (in `sync_conflict_resolver.dart`) wires them into
/// the sync worker's push loop.
library;

/// A versioned mutation used to compare local vs remote state.
class MutationVersion {
  /// The entity this mutation targets (e.g. a message id, a profile field).
  final String entityId;

  /// Wall-clock of the write. Server-authoritative when [serverAcknowledged]
  /// is true, local otherwise.
  final DateTime timestamp;

  /// True when this version was acknowledged/persisted by the server.
  final bool serverAcknowledged;

  /// Deterministic tiebreak discriminator (e.g. blind_hash_id of the author).
  /// Never PII — hashes only.
  final String authorHash;

  /// Optional numeric aggregate carried by this version (Task 5.5).
  ///
  /// When BOTH sides of a conflict carry a value for the same entity, the
  /// engine may MERGE them via a [MergePolicy] instead of declaring a winner
  /// (e.g. karma scores: both votes count). `null` means the version has no
  /// mergeable aggregate (a simple field edit — LWW applies).
  final num? value;

  const MutationVersion({
    required this.entityId,
    required this.timestamp,
    required this.serverAcknowledged,
    required this.authorHash,
    this.value,
  });
}

/// The outcome of a conflict resolution.
enum ConflictDecision {
  /// The local version wins; it should be (re)submitted to the server.
  applyLocal,

  /// The remote version wins; local state should be overwritten.
  applyRemote,

  /// Both sides' aggregate values were merged deterministically (Task 5.5);
  /// the merged value should be written locally and (re)submitted.
  merge,
}

/// Result of consulting a [ConflictResolutionPolicy].
class ConflictResolution {
  final ConflictDecision decision;
  final MutationVersion winner;

  /// The merged aggregate value when [decision] is [ConflictDecision.merge]
  /// (Task 5.5). Null for applyLocal/applyRemote outcomes.
  final num? mergedValue;

  const ConflictResolution(
    this.decision,
    this.winner, {
    this.mergedValue,
  });
}

/// Policy for deciding which divergent version wins (Task 5.2 hook).
///
/// Implementations MUST be deterministic: given the same two inputs, they
/// always return the same [ConflictDecision], so all devices converge.
abstract class ConflictResolutionPolicy {
  ConflictResolution resolve({
    required MutationVersion local,
    required MutationVersion remote,
  });
}

/// Server-authoritative last-write-wins policy (default, Task 5.2).
///
/// Ordering (strictly deterministic):
/// 1. A server-acknowledged version beats a local-only version — the server
///    is authoritative for what actually happened.
/// 2. Otherwise, the newer [MutationVersion.timestamp] wins.
/// 3. Exact timestamp ties break on [MutationVersion.authorHash] (byte order),
///    so replicas never disagree even in a tie.
class ServerAuthoritativeLastWriteWins implements ConflictResolutionPolicy {
  const ServerAuthoritativeLastWriteWins();

  @override
  ConflictResolution resolve({
    required MutationVersion local,
    required MutationVersion remote,
  }) {
    final winner = _winner(local, remote);
    return ConflictResolution(
      winner == local
          ? ConflictDecision.applyLocal
          : ConflictDecision.applyRemote,
      winner,
    );
  }

  MutationVersion _winner(MutationVersion local, MutationVersion remote) {
    // Rule 1: server acknowledgment is authoritative.
    if (local.serverAcknowledged != remote.serverAcknowledged) {
      return local.serverAcknowledged ? local : remote;
    }

    // Rule 2: newer timestamp wins.
    if (local.timestamp != remote.timestamp) {
      return local.timestamp.isAfter(remote.timestamp) ? local : remote;
    }

    // Rule 3: deterministic tiebreak — never depends on ordering or clocks.
    return local.authorHash.compareTo(remote.authorHash) >= 0 ? local : remote;
  }
}

/// Deterministic merge for an aggregate field (Task 5.5).
///
/// Merge policies combine two numeric snapshots of the same aggregate (e.g.
/// karma scores) into one value. A correct merge is:
/// - **Commutative:** merge(a, b) == merge(b, a) — argument order never
///   matters, so replicas converge regardless of which side they label
///   "local" or "remote".
/// - **Idempotent:** merge(a, a) == a — replaying the same version (or
///   merging a version with itself after a network retry) never double-counts.
/// - **Associative:** merge(merge(a, b), c) == merge(a, merge(b, c)) —
///   multi-device convergence is order-independent.
abstract class MergePolicy {
  /// Merges [localValue] and [remoteValue] (either may be null — a null
  /// side contributes nothing, the other side's value is kept).
  num? merge(num? localValue, num? remoteValue);
}

/// Max-merge for monotonic aggregates such as karma scores (Task 5.5).
///
/// Karma is a non-decreasing score within a merge window (a vote only ever
/// adds), so the convergent merge is the MAX of the two snapshots: every
/// increment that any device saw is preserved, and the merge is trivially
/// commutative, associative and idempotent — no double counting, no
/// split-brain, no dependence on which device synced first.
class MaxMergePolicy implements MergePolicy {
  const MaxMergePolicy();

  @override
  num? merge(num? localValue, num? remoteValue) {
    if (localValue == null) {
      return remoteValue;
    }
    if (remoteValue == null) {
      return localValue;
    }
    return localValue >= remoteValue ? localValue : remoteValue;
  }
}

/// Composite policy: merge aggregate values, otherwise last-write-wins
/// (Task 5.5).
///
/// When BOTH sides of a conflict carry a [MutationVersion.value] for the
/// same entity, the [mergePolicy] combines them and the outcome is
/// [ConflictDecision.merge] (winner = the version that contributed the
/// merged value, so [ConflictResolution.winner] stays meaningful). When
/// either side lacks an aggregate (simple-field edit), the [base] LWW policy
/// decides exactly as in Task 5.2 — preserving all existing semantics.
class MergeAwareLastWriteWins implements ConflictResolutionPolicy {
  final ConflictResolutionPolicy base;
  final MergePolicy mergePolicy;

  const MergeAwareLastWriteWins({
    this.base = const ServerAuthoritativeLastWriteWins(),
    this.mergePolicy = const MaxMergePolicy(),
  });

  @override
  ConflictResolution resolve({
    required MutationVersion local,
    required MutationVersion remote,
  }) {
    final bothCarryAggregates = local.value != null &&
        remote.value != null &&
        local.entityId == remote.entityId;
    if (bothCarryAggregates) {
      final merged = mergePolicy.merge(local.value, remote.value);
      // Winner = the version that contributed the merged value (tie-breaks on
      // the merged value equality: when both sides already agree, prefer the
      // base LWW ordering so the winner is still deterministic).
      final winner = _contributingWinner(local, remote, merged);
      return ConflictResolution(
        ConflictDecision.merge,
        winner,
        mergedValue: merged,
      );
    }
    return base.resolve(local: local, remote: remote);
  }

  MutationVersion _contributingWinner(
    MutationVersion local,
    MutationVersion remote,
    num? merged,
  ) {
    if (local.value == merged && remote.value != merged) {
      return local;
    }
    if (remote.value == merged && local.value != merged) {
      return remote;
    }
    // Both sides already equal the merged value (or the merge is a no-op):
    // fall back to the base LWW tie-break for a deterministic winner.
    return base.resolve(local: local, remote: remote).winner;
  }
}
