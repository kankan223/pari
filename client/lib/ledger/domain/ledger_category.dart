/// Ledger post categories (DESIGN.md §4.4, PRD §6.1).
///
/// Posts divide into structured categories rather than a chaotic timeline.
/// Each category maps to a pillar accent color for its [CategoryChip] —
/// the color mapping lives in the UI layer (LedgerTheme), this enum is the
/// canonical domain identity.
enum LedgerCategory {
  /// #CivicInfrastructure — potholes, water distribution, public fund
  /// diversion. Rendered in Ledger Green.
  civicInfrastructure,

  /// #StudentRights — exam leaks, institutional bribery, admission scams.
  /// Rendered in Academy Teal.
  studentRights,

  /// #ConsumerWatch — local price gouging, corporate malfeasance.
  /// Rendered in War Room Amber.
  consumerWatch,

  /// #SatireAndCulture — community memes, political satire, local civic
  /// challenges. Rendered in Civic Gold.
  satireAndCulture,

  /// #BreakingLocal — urgent local news. Rendered in Alert Red (sparingly).
  breakingLocal;

  /// The display label shown on chips and cards (DESIGN.md §4.4: 11sp Noto
  /// Sans Medium, tracked). e.g. `#CIVIC INFRA`.
  String get label => switch (this) {
        LedgerCategory.civicInfrastructure => '#CIVIC INFRA',
        LedgerCategory.studentRights => '#STUDENTS',
        LedgerCategory.consumerWatch => '#CONSUMER',
        LedgerCategory.satireAndCulture => '#SATIRE',
        LedgerCategory.breakingLocal => '#BREAKING',
      };

  /// The full category name (compose dropdown + accessibility).
  String get fullName => switch (this) {
        LedgerCategory.civicInfrastructure => 'Civic Infrastructure',
        LedgerCategory.studentRights => 'Student Rights',
        LedgerCategory.consumerWatch => 'Consumer Watch',
        LedgerCategory.satireAndCulture => 'Satire & Culture',
        LedgerCategory.breakingLocal => 'Breaking Local',
      };

  /// Stable wire identifier (server contract, never rendered).
  String get wireName => switch (this) {
        LedgerCategory.civicInfrastructure => 'civic_infrastructure',
        LedgerCategory.studentRights => 'student_rights',
        LedgerCategory.consumerWatch => 'consumer_watch',
        LedgerCategory.satireAndCulture => 'satire_and_culture',
        LedgerCategory.breakingLocal => 'breaking_local',
      };

  /// Parses a wire name, throwing [ArgumentError] for unknown values
  /// (strict bounds — a server can never smuggle an unknown category in).
  static LedgerCategory fromWireName(String name) => switch (name) {
        'civic_infrastructure' => LedgerCategory.civicInfrastructure,
        'student_rights' => LedgerCategory.studentRights,
        'consumer_watch' => LedgerCategory.consumerWatch,
        'satire_and_culture' => LedgerCategory.satireAndCulture,
        'breaking_local' => LedgerCategory.breakingLocal,
        _ => throw ArgumentError('Unknown ledger category: $name'),
      };
}
