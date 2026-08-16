/// Lifecycle of a War Room case (DESIGN.md §8.4 status timeline).
///
/// The detail view renders the timeline as: filed → auto-triage →
/// analysts assigned → investigation ongoing → report ready. The status
/// below is the victim-facing snapshot; the full immutable timeline lives
/// with the case record and is rendered as checkpoints.
///
/// SECURITY CHECKPOINT (Task 8.1): status is a public case attribute —
/// never identity-bearing.
enum CaseStatus {
  /// The victim is mid-intake; not yet visible to analysts.
  draft,

  /// Filed and awaiting/undergoing triage.
  underInvestigation,

  /// Analysts are actively investigating (timeline: investigation ongoing).
  investigationOngoing,

  /// A Verified Intel Report is ready.
  reportReady,

  /// The victim withdrew the case (one-tap control, PRD §7.3-4).
  withdrawn,

  /// Case closed (report delivered or withdrawn finalized).
  closed;

  /// Strict wire/label name — the text rendered in status lines.
  String get label => switch (this) {
        CaseStatus.draft => 'DRAFT',
        CaseStatus.underInvestigation => 'UNDER INVESTIGATION',
        CaseStatus.investigationOngoing => 'INVESTIGATION ONGOING',
        CaseStatus.reportReady => 'REPORT READY',
        CaseStatus.withdrawn => 'WITHDRAWN',
        CaseStatus.closed => 'CLOSED',
      };
}
