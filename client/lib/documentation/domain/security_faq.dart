/// Security FAQ domain models for handover documentation (Task 15.4).
///
/// Defines structured security FAQ content for end users: questions about
/// encryption, privacy, data handling, and account security. All values
/// are pure — no identity, no PII, no secrets, no credentials.

/// Category of security FAQ entry.
enum SecurityFaqCategory {
  /// Questions about encryption and data protection.
  encryption,

  /// Questions about account security and authentication.
  accountSecurity,

  /// Questions about privacy and data collection.
  privacy,

  /// Questions about data sharing and third parties.
  dataSharing,

  /// Questions about incident reporting.
  incidentReporting,

  /// Questions about compliance and regulations.
  compliance;

  /// Human-readable label.
  String get label {
    switch (this) {
      case SecurityFaqCategory.encryption:
        return 'Encryption & Data Protection';
      case SecurityFaqCategory.accountSecurity:
        return 'Account Security';
      case SecurityFaqCategory.privacy:
        return 'Privacy';
      case SecurityFaqCategory.dataSharing:
        return 'Data Sharing';
      case SecurityFaqCategory.incidentReporting:
        return 'Incident Reporting';
      case SecurityFaqCategory.compliance:
        return 'Compliance & Regulations';
    }
  }
}

/// A single security FAQ entry.
class SecurityFaqEntry {
  /// Unique identifier (e.g., 'SEC-FAQ-001').
  final String id;

  /// The security question.
  final String question;

  /// The answer (may contain Markdown).
  final String answer;

  /// Category.
  final SecurityFaqCategory category;

  /// Search keywords for discoverability.
  final List<String> keywords;

  /// Related FAQ entry IDs.
  final List<String> relatedEntries;

  /// Whether this entry is currently active.
  final bool isActive;

  const SecurityFaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    this.category = SecurityFaqCategory.encryption,
    this.keywords = const [],
    this.relatedEntries = const [],
    this.isActive = true,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityFaqEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection of security FAQ entries.
class SecurityFaqCollection {
  /// All entries indexed by ID.
  final Map<String, SecurityFaqEntry> _entries;

  const SecurityFaqCollection({Map<String, SecurityFaqEntry> entries = const {}})
      : _entries = entries;

  /// Create an empty collection.
  factory SecurityFaqCollection.empty() => const SecurityFaqCollection();

  /// All entries.
  List<SecurityFaqEntry> get all => _entries.values.toList();

  /// Number of entries.
  int get count => _entries.length;

  /// Get entry by ID.
  SecurityFaqEntry? getById(String id) => _entries[id];

  /// Get entries by category.
  List<SecurityFaqEntry> getByCategory(SecurityFaqCategory category) =>
      _entries.values.where((e) => e.category == category).toList();

  /// Get only active entries.
  List<SecurityFaqEntry> get active =>
      _entries.values.where((e) => e.isActive).toList();

  /// Search entries by keyword (case-insensitive).
  List<SecurityFaqEntry> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _entries.values.where((e) {
      if (e.question.toLowerCase().contains(lowerQuery)) return true;
      if (e.answer.toLowerCase().contains(lowerQuery)) return true;
      return e.keywords.any((k) => k.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Categories present in this collection.
  Set<SecurityFaqCategory> get categories =>
      _entries.values.map((e) => e.category).toSet();

  /// Add an entry.
  SecurityFaqCollection withEntry(SecurityFaqEntry entry) {
    return SecurityFaqCollection(entries: Map.from(_entries)..[entry.id] = entry);
  }

  /// Remove an entry.
  SecurityFaqCollection withoutEntry(String id) {
    return SecurityFaqCollection(entries: Map.from(_entries)..remove(id));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityFaqCollection &&
          runtimeType == other.runtimeType &&
          _mapEquals(_entries, other._entries);

  @override
  int get hashCode =>
      Object.hashAll(_entries.entries.map((e) => Object.hash(e.key, e.value)));

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
