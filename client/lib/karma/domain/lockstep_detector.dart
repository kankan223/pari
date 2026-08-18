import 'karma_calculation.dart';

/// One voter's contribution to a tally, for lockstep analysis (Task 10.2).
///
/// SECURITY CHECKPOINT (10.2): the voter is identified ONLY by their
/// validated 64-hex blind hash — zero PII ever enters the detector.
class KarmaVote {
  /// The voter's 64-hex blind hash (never rendered).
  final String voterHash;

  /// The voter's account age in days (public tenure, not identity).
  final int accountAgeDays;

  /// When the vote was cast.
  final DateTime at;

  const KarmaVote({
    required this.voterHash,
    required this.accountAgeDays,
    required this.at,
  });
}

/// Deterministic anomaly detection for LOCKSTEP voting (PRD §9.2, Task 10.2).
///
/// Sybil resistance without banning: when a tally receives a CLUSTER of
/// votes from accounts that are (a) all very new and (b) all cast within a
/// short window, the votes' combined weight is DAMPENED algorithmically.
/// Genuine new local communities are never banned — only the anomalous
/// cluster loses weight, and the damping is fully deterministic so every
/// device converges on the same outcome.
///
/// Rule (fixed, test-enforced):
///   A cluster = [clusterSize] or more votes from distinct voters that
///   (a) are each younger than [newAccountAgeDays] days and
///   (b) all fall within a [clusterWindow] timespan.
///   When a cluster exists, the tally weight is multiplied by
///   [dampeningFactor] (e.g. 25%); otherwise [noDampening] (100%).
///
/// Pure function of the vote list — no randomness, no wall-clock beyond the
/// supplied timestamps, no server round-trip.
class LockstepDetector {
  const LockstepDetector._();

  /// Votes needed to form an anomalous cluster.
  static const int clusterSize = 3;

  /// Accounts younger than this many days count as "new" for clustering.
  static const int newAccountAgeDays = 30;

  /// Votes within this timespan count as "in lockstep".
  static const Duration clusterWindow = Duration(minutes: 10);

  /// Dampened multiplier when a cluster is detected (25%).
  static const double dampeningFactor = 0.25;

  /// Full multiplier when no cluster is detected.
  static const double noDampening = 1.0;

  /// Returns the weight multiplier for [votes] (1.0 normally, 0.25 when a
  /// lockstep cluster is detected).
  static double dampeningFor(List<KarmaVote> votes) {
    if (votes.length < clusterSize) {
      return noDampening;
    }

    // Deterministic scan: sort by cast time, then slide a window of
    // [clusterWindow]; count DISTINCT new voters inside each window.
    final sorted = [...votes]..sort((a, b) => a.at.compareTo(b.at));
    final newVoters =
        sorted.where((v) => v.accountAgeDays < newAccountAgeDays).toList();

    for (var i = 0; i < newVoters.length; i++) {
      final windowStart = newVoters[i].at;
      final inWindow = <String>{};
      for (var j = i; j < newVoters.length; j++) {
        if (newVoters[j].at.difference(windowStart) > clusterWindow) {
          break;
        }
        inWindow.add(newVoters[j].voterHash);
      }
      if (inWindow.length >= clusterSize) {
        return dampeningFactor;
      }
    }
    return noDampening;
  }

  /// Convenience: the dampened [KarmaVoteWeight.weight] for [karma] when a
  /// cluster is detected, as a double (used by projections — never by the
  /// persisted ledger, which stores only the raw integer weight).
  static double dampenedWeight({
    required int karma,
    required List<KarmaVote> votes,
  }) {
    final base = KarmaVoteWeight.weight(karma: karma).toDouble();
    return base * dampeningFor(votes);
  }
}
