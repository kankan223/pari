import 'ledger_post.dart';
import 'peer_review.dart';

/// Deterministic Peer Review Gate rules (Task 7.6, PRD FR-L3/FR-L4).
///
/// The Ledger's trust pipeline:
/// 1. **Shadow Queue (FR-L3)** — accounts younger than 96h post into the
///    shadow queue (their posts are held out of the live feed).
/// 2. **Karma fast-track** — high-karma accounts skip review and publish
///    immediately (fast-track publishing).
/// 3. **Peer Review Gate (FR-L4)** — every other post enters review and
///    needs **3/3 reviewer approvals** to transition to `published`.
///
/// SECURITY CONTRACT (Task 7.6): every rule is PURE and DETERMINISTIC —
/// no wall-clock beyond the injectable [now], no randomness in outcomes,
/// and reviewer assignment produces ONLY blinded display handles from
/// opaque blind-hash inputs (never the hashes themselves, never PII).
class PeerReviewGate {
  const PeerReviewGate._();

  /// Consensus required to publish a reviewed post (3 reviewers, PRD FR-L4).
  static const int consensusRequired = 3;

  /// Shadow Queue window: accounts younger than this post to the shadow
  /// queue (PRD FR-L3: <96 hours).
  static const Duration shadowQueueWindow = Duration(hours: 96);

  /// Karma threshold above which a post fast-tracks straight to published.
  static const int fastTrackKarmaThreshold = 100;

  /// Returns true when [approvedCount] approvals reach the 3/3 consensus.
  static bool hasConsensus(int approvedCount) =>
      approvedCount >= consensusRequired;

  /// Decides the ENTRY status for a post authored by an account of age
  /// [accountAge] with [karma].
  ///
  /// Deterministic: same inputs always yield the same status.
  static LedgerPostStatus entryStatus({
    required Duration accountAge,
    required int karma,
  }) {
    if (accountAge < shadowQueueWindow) {
      return LedgerPostStatus.shadowQueue;
    }
    if (karma >= fastTrackKarmaThreshold) {
      return LedgerPostStatus.published; // fast-track
    }
    return LedgerPostStatus.peerReview;
  }

  /// The status after a review decision on a post currently in [current]
  /// status with [approvedCount] approvals:
  /// - an `approved` decision increments the count; reaching the 3/3
  ///   consensus publishes the post;
  /// - any other decision leaves the status unchanged (the post stays in
  ///   review; rejected/flagged decisions are still recorded and synced).
  static LedgerPostStatus statusAfterReview({
    required LedgerPostStatus current,
    required PeerReviewDecision decision,
    required int approvedCount,
  }) {
    if (current == LedgerPostStatus.published) {
      return LedgerPostStatus.published; // immutable once published
    }
    final isApproval = decision == PeerReviewDecision.approved;
    final nextCount = isApproval ? approvedCount + 1 : approvedCount;
    if (hasConsensus(nextCount)) {
      return LedgerPostStatus.published;
    }
    // A shadow-queue post that gets reviewed stays in review once its
    // window is served; reviewable posts stay in peer review.
    return LedgerPostStatus.peerReview;
  }

  /// Assigns up to [consensusRequired] blinded reviewers for [postId],
  /// chosen deterministically from [candidateBlindHashes] (opaque 64-hex
  /// blind-hash ids).
  ///
  /// SECURITY CHECKPOINT 7.6: the returned handles are DERIVED DISPLAY
  /// handles (`reviewer_` + short hex digest) — the raw blind hashes are
  /// never returned, never logged, never rendered. The selection is
  /// deterministic (seeded by the post id), so every device converges on
  /// the same assignment without split-brain.
  static List<String> assignReviewers(
    String postId,
    List<String> candidateBlindHashes,
  ) {
    final selected = <String>[];
    if (candidateBlindHashes.isEmpty) {
      return selected;
    }
    // Deterministic seeded order (stable across devices — never Random()).
    final seed = _seedOf(postId);
    final indices = List.generate(candidateBlindHashes.length, (i) => i)
      ..sort((a, b) {
        final ha = _mix(seed, a);
        final hb = _mix(seed, b);
        final byHash = ha.compareTo(hb);
        return byHash != 0 ? byHash : a.compareTo(b);
      });
    for (var i = 0;
        i < indices.length && selected.length < consensusRequired;
        i++) {
      selected.add(_blindedHandle(candidateBlindHashes[indices[i]]));
    }
    return selected;
  }

  /// Derives a NON-PII display handle from an opaque blind hash.
  /// e.g. `a1b2c3d4e5f6...` -> `reviewer_a1b2c3`.
  static String _blindedHandle(String blindHash) {
    final digest = _shortDigest(blindHash);
    return 'reviewer_$digest';
  }

  /// First 6 hex chars of a stable FNV-1a digest of [input] (deterministic,
  /// non-cryptographic — this is a display handle, not a secret).
  static String _shortDigest(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0').substring(0, 6);
  }

  static int _seedOf(String input) {
    var seed = 0;
    for (final unit in input.codeUnits) {
      seed = (seed * 31 + unit) & 0x7fffffff;
    }
    return seed;
  }

  /// Deterministic mix of [seed] and index for stable ordering.
  static int _mix(int seed, int i) {
    var x = seed ^ (i * 0x9e3779b9 & 0x7fffffff);
    x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
    x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
    return (x >> 16) ^ x;
  }

  /// The blinded handle derivation, exposed for tests to prove display
  /// handles never equal raw blind hashes.
  static String blindedHandleFor(String blindHash) => _blindedHandle(blindHash);
}
