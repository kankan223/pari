/// A karma-gated privilege (PRD §9.2).
///
/// Every gate is a FIXED deterministic threshold — the same score always
/// satisfies the same gate on every device. Gates operate ONLY on the
/// public karma score and (for the Moderator Council) the account's age;
/// zero identity ever enters the check.
enum KarmaGate {
  /// Skip-probation posting: publish Ledger posts immediately (≥ 50).
  skipProbationPosting('skip_probation_posting', 50,
      label: 'Post without probation'),

  /// Peer Review Gate voting rights (≥ 100).
  peerReviewVoting('peer_review_voting', 100, label: 'Peer Review voting'),

  /// War Room analyst application eligibility (≥ 150, plus the vetting
  /// gauntlet — handled separately in Task 8.5).
  warRoomAnalystEligibility(
    'war_room_analyst_eligibility',
    150,
    label: 'War Room analyst eligibility',
  ),

  /// Moderator Council eligibility (≥ 500 AND 90-day tenure).
  moderatorCouncil(
    'moderator_council',
    500,
    label: 'Moderator Council eligibility',
    tenureDays: 90,
  );

  const KarmaGate(this.wireName, this.threshold,
      {required this.label, this.tenureDays});

  /// Wire name for persistence + sync frames.
  final String wireName;

  /// The karma threshold the score must reach.
  final int threshold;

  /// Fixed, non-sensitive display label.
  final String label;

  /// Additional account-age requirement (days), or null for score-only.
  final int? tenureDays;

  /// Whether [karma] satisfies this gate given [accountAgeDays] of tenure.
  ///
  /// Score-only gates ignore tenure; the Moderator Council additionally
  /// requires the 90-day account age (PRD §9.2).
  bool isSatisfied({required int karma, required int accountAgeDays}) {
    final tenure = tenureDays;
    if (karma < threshold) {
      return false;
    }
    return tenure == null || accountAgeDays >= tenure;
  }

  /// Strict wire decode — unknown gates throw.
  static KarmaGate fromWireName(String raw) => switch (raw) {
        'skip_probation_posting' => KarmaGate.skipProbationPosting,
        'peer_review_voting' => KarmaGate.peerReviewVoting,
        'war_room_analyst_eligibility' => KarmaGate.warRoomAnalystEligibility,
        'moderator_council' => KarmaGate.moderatorCouncil,
        _ => throw ArgumentError('Unknown karma gate: $raw'),
      };
}
