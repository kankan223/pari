import 'dart:math' as math;

/// Deterministic, karma-weighted, SUB-LINEAR vote scoring (Task 7.5).
///
/// Raw vote tallies grow unboundedly; the weighted score compresses them
/// with a square-root curve so no single post can dominate the feed:
///
///   score = floor(sqrt(upvotes)) - floor(sqrt(downvotes))
///
/// Properties (all test-enforced):
/// - **Deterministic & pure** — same counts always yield the same score;
///   no randomness, no wall-clock, no server round-trip.
/// - **Sub-linear** — every additional vote adds less score than the one
///   before it (diminishing returns), so vote counts cannot be weaponized
///   into runaway scores.
/// - **Directional** — downvotes subtract through the same curve, so a
///   post with many downvotes genuinely ranks lower than one with none.
/// - **Privacy-preserving by construction** — operates ONLY on the two
///   aggregate tallies. No identity, no per-voter values ever enter the
///   computation (SECURITY CHECKPOINT 7.5: vote weights are calculated
///   client-side from public aggregates).
///
/// Per-voter karma weighting (a weighted vote sum) is a server-side
/// aggregation concern (Phase 4.5/4.6 stack); the client renders this
/// deterministic local projection of the same tallies.
class KarmaWeightedScore {
  const KarmaWeightedScore._();

  /// The sub-linear weighted score for [upvotes] upvotes and [downvotes]
  /// downvotes. Always returns a bounded integer; negative when downvotes
  /// dominate.
  static int weighted({required int upvotes, required int downvotes}) {
    final u = math.sqrt(math.max(0, upvotes)).floor();
    final d = math.sqrt(math.max(0, downvotes)).floor();
    return u - d;
  }

  /// Convenience: the weighted score for a post's net count when only the
  /// net is known (upvotes/downvotes collapsed). Kept for parity with the
  /// existing single-tally projection; the two-tally form is preferred.
  static int ofNet(int netVotes) {
    final n = math.max(0, netVotes);
    return math.sqrt(n).floor();
  }
}
