/// War Room case severity (DESIGN.md §8.2, PRD FR-W2).
///
/// The victim-facing UI shows these as colored classification bands
/// (CRITICAL / HIGH / MEDIUM / LOW). Severity is a PUBLIC case attribute —
/// it drives SLA targets and triage — and carries no identity.
///
/// SECURITY CHECKPOINT (Task 8.1): these are fixed, non-sensitive
/// presentation constants. A severity band can never leak who filed the
/// case or any payload content.
enum CaseSeverity {
  critical,
  high,
  medium,
  low;

  /// Strict wire/label name — the exact text rendered inside the band.
  String get label => switch (this) {
        CaseSeverity.critical => 'CRITICAL',
        CaseSeverity.high => 'HIGH',
        CaseSeverity.medium => 'MEDIUM',
        CaseSeverity.low => 'LOW',
      };

  /// Rank used for deterministic comparisons (critical > high > medium > low).
  /// The provisional severity merge in the intake flow relies on this order.
  int get rank => switch (this) {
        CaseSeverity.critical => 3,
        CaseSeverity.high => 2,
        CaseSeverity.medium => 1,
        CaseSeverity.low => 0,
      };

  /// The more severe of [a] and [b] — a pure, deterministic merge (the
  /// War Room never lets a victim-selected urgency DOWNGRADE a serious
  /// situation category).
  static CaseSeverity maxSeverity(CaseSeverity a, CaseSeverity b) =>
      a.rank >= b.rank ? a : b;
}
