import 'dart:math' as math;

/// Sub-linear karma-weighted vote power (Task 10.2, PRD §9.2).
///
/// A voter's karma scales their vote weight SUB-LINEARLY: every additional
/// point of karma adds less weight than the one before it, so no single
/// high-karma account can dominate a tally. Mirrors the feed-side
/// `KarmaWeightedScore` sqrt curve (Task 7.5) but for the PER-VOTER weight:
///
///   weight = min(maxWeight, 1 + floor(sqrt(karma)))
///
/// Properties (all test-enforced):
/// - **Deterministic & pure** — same karma always yields the same weight;
///   no randomness, no wall-clock, no server round-trip.
/// - **Sub-linear** — diminishing returns on karma.
/// - **Floored at 1** — a brand-new account (karma 0) still casts a real
///   vote, so communities can't be silenced by score alone.
/// - **Capped** — [maxWeight] bounds the ceiling.
/// - **Privacy-preserving by construction** — operates ONLY on the integer
///   karma score; no identity, no blind hash, no per-voter value enters.
class KarmaVoteWeight {
  const KarmaVoteWeight._();

  /// Maximum weight a single vote can carry (a 10-karma vote reaches it).
  static const int maxWeight = 10;

  /// The sub-linear vote weight for a voter with [karma].
  ///
  /// karma  0 → 1
  /// karma  1 → 2
  /// karma  9 → 4   (sqrt 3 → 4)
  /// karma 81 → 10  (sqrt 9 → 10 — capped at [maxWeight])
  static int weight({required int karma}) {
    final k = math.max(0, karma);
    return math.min(maxWeight, 1 + math.sqrt(k).floor());
  }
}
