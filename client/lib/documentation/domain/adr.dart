/// Architecture Decision Records (ADR) domain models (Task 15.1).
///
/// ADRs capture important architectural decisions along with their context
/// and consequences. All values are pure — no identity, no PII, no secrets.

/// Status of an ADR.
enum AdrStatus {
  /// Decision is proposed but not yet accepted.
  proposed,

  /// Decision has been accepted.
  accepted,

  /// Decision has been deprecated.
  deprecated,

  /// Decision has been superseded by another ADR.
  superseded;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);
}

/// A single Architecture Decision Record.
class Adr {
  /// Unique identifier (e.g., 'ADR-001').
  final String id;

  /// Short title of the decision.
  final String title;

  /// Current status.
  final AdrStatus status;

  /// Date the decision was made (ISO 8601).
  final String date;

  /// Context: what is the issue that motivates this decision?
  final String context;

  /// Decision: what is the change being proposed or decided?
  final String decision;

  /// Consequences: what are the resulting outcomes?
  final String consequences;

  /// Alternatives considered (may be empty).
  final List<String> alternatives;

  /// Related ADR IDs (may be empty).
  final List<String> relatedAdrs;

  /// Tags for categorization.
  final List<String> tags;

  const Adr({
    required this.id,
    required this.title,
    required this.status,
    required this.date,
    required this.context,
    required this.decision,
    required this.consequences,
    this.alternatives = const [],
    this.relatedAdrs = const [],
    this.tags = const [],
  });

  /// Whether this ADR is still active (accepted or proposed).
  bool get isActive =>
      status == AdrStatus.accepted || status == AdrStatus.proposed;

  /// Whether this ADR is historical (deprecated or superseded).
  bool get isHistorical =>
      status == AdrStatus.deprecated || status == AdrStatus.superseded;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Adr &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection of ADRs with lookup capabilities.
class AdrRegistry {
  /// All ADRs indexed by ID.
  final Map<String, Adr> _adrs;

  const AdrRegistry({Map<String, Adr> adrs = const {}}) : _adrs = adrs;

  /// Create an empty registry.
  factory AdrRegistry.empty() => const AdrRegistry();

  /// All ADRs.
  List<Adr> get all => _adrs.values.toList();

  /// Number of ADRs.
  int get count => _adrs.length;

  /// Get ADR by ID.
  Adr? getById(String id) => _adrs[id];

  /// Get all accepted ADRs.
  List<Adr> get accepted =>
      _adrs.values.where((a) => a.status == AdrStatus.accepted).toList();

  /// Get all proposed ADRs.
  List<Adr> get proposed =>
      _adrs.values.where((a) => a.status == AdrStatus.proposed).toList();

  /// Get all active ADRs.
  List<Adr> get active => _adrs.values.where((a) => a.isActive).toList();

  /// Get ADRs by tag.
  List<Adr> getByTag(String tag) =>
      _adrs.values.where((a) => a.tags.contains(tag)).toList();

  /// Add an ADR to the registry.
  AdrRegistry withAdr(Adr adr) {
    return AdrRegistry(adrs: Map.from(_adrs)..[adr.id] = adr);
  }

  /// Remove an ADR from the registry.
  AdrRegistry withoutAdr(String id) {
    return AdrRegistry(adrs: Map.from(_adrs)..remove(id));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AdrRegistry &&
          runtimeType == other.runtimeType &&
          _mapEquals(_adrs, other._adrs);

  @override
  int get hashCode => Object.hashAll(_adrs.entries.map((e) => Object.hash(e.key, e.value)));

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
