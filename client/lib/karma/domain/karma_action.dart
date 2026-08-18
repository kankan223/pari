/// The pillar that earned (or lost) karma (PRD §9.2).
///
/// Cross-pillar by design: karma is the ONE score shared across the Vault,
/// Ledger, War Room, and Academy. The pillar is an opaque enum — zero
/// identity by construction.
enum KarmaPillar {
  /// The Daily Ledger (civic feed posts + Peer Review Gate).
  ledger('ledger'),

  /// The War Room (OSINT case contributions, analyst vetting).
  warRoom('war_room'),

  /// The Academy (sandbox notes, module completions).
  academy('academy'),

  /// Cross-pillar events (abuse reports).
  crossPillar('cross_pillar');

  const KarmaPillar(this.wireName);

  /// Wire name for persistence + sync frames.
  final String wireName;

  /// Strict wire decode — unknown pillars throw (a corrupt/forged row can
  /// never masquerade as a real pillar).
  static KarmaPillar fromWireName(String raw) => switch (raw) {
        'ledger' => KarmaPillar.ledger,
        'war_room' => KarmaPillar.warRoom,
        'academy' => KarmaPillar.academy,
        'cross_pillar' => KarmaPillar.crossPillar,
        _ => throw ArgumentError('Unknown karma pillar: $raw'),
      };
}

/// A karma-earning (or karma-losing) action (PRD §9.2 table).
///
/// Every action carries a FIXED, deterministic delta — the same action
/// always moves karma by the same amount on every device:
///
///   +5  Ledger post confirmed accurate by the Peer Review Gate
///   +15 War Room case contribution on a closed case
///   +3  Sandbox note upvoted by 3+ peers
///   +2  Academy module completed
///   +20 Successfully vetted as a War Room analyst (one-time)
///   −3  Post rejected by the Peer Review Gate
///   −25 Confirmed abuse report against the user (cross-pillar)
///
/// SECURITY CHECKPOINT (Task 10.2): an action is ZERO-IDENTITY — it is a
/// wire code + a pillar + a delta. The actor is carried separately as a
/// validated 64-hex blind hash ([KarmaEvent.actorHash]); no handle, phone,
/// email, or identity can be an action.
enum KarmaAction {
  ledgerPostVerified(
    'ledger_post_verified',
    KarmaPillar.ledger,
    5,
    label: 'Post confirmed by peer review',
  ),
  warRoomCaseContribution(
    'war_room_case_contribution',
    KarmaPillar.warRoom,
    15,
    label: 'War Room case contribution',
  ),
  sandboxNoteUpvoted3(
    'sandbox_note_upvoted_3',
    KarmaPillar.academy,
    3,
    label: 'Sandbox note upvoted by peers',
  ),
  academyModuleCompleted(
    'academy_module_completed',
    KarmaPillar.academy,
    2,
    label: 'Academy module completed',
  ),
  warRoomAnalystVetted(
    'war_room_analyst_vetted',
    KarmaPillar.warRoom,
    20,
    label: 'War Room analyst vetted',
    oneTime: true,
  ),
  ledgerPostRejected(
    'ledger_post_rejected',
    KarmaPillar.ledger,
    -3,
    label: 'Post rejected by peer review',
  ),
  confirmedAbuseReport(
    'confirmed_abuse_report',
    KarmaPillar.crossPillar,
    -25,
    label: 'Confirmed abuse report',
  );

  const KarmaAction(this.wireName, this.pillar, this.delta,
      {required this.label, this.oneTime = false});

  /// Wire name for persistence + sync frames.
  final String wireName;

  /// The pillar this action belongs to.
  final KarmaPillar pillar;

  /// The fixed karma delta (+gain / −loss).
  final int delta;

  /// Fixed, non-sensitive display label (the ONLY text rendered for an
  /// action — never a payload).
  final String label;

  /// One-time actions (e.g. analyst vetting) may only accrue once.
  final bool oneTime;

  /// Strict wire decode — unknown actions throw (a corrupt/forged row can
  /// never masquerade as a real action).
  static KarmaAction fromWireName(String raw) => switch (raw) {
        'ledger_post_verified' => KarmaAction.ledgerPostVerified,
        'war_room_case_contribution' => KarmaAction.warRoomCaseContribution,
        'sandbox_note_upvoted_3' => KarmaAction.sandboxNoteUpvoted3,
        'academy_module_completed' => KarmaAction.academyModuleCompleted,
        'war_room_analyst_vetted' => KarmaAction.warRoomAnalystVetted,
        'ledger_post_rejected' => KarmaAction.ledgerPostRejected,
        'confirmed_abuse_report' => KarmaAction.confirmedAbuseReport,
        _ => throw ArgumentError('Unknown karma action: $raw'),
      };
}
