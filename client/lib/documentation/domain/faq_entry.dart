/// FAQ (Frequently Asked Questions) entry domain models (Task 15.3).
///
/// Defines structured FAQ content with categorization, search keywords,
/// and helpfulness tracking. All values are pure — no identity, no PII,
/// no secrets.

/// Category for FAQ entries.
enum FaqCategory {
  /// Getting started and onboarding.
  gettingStarted,

  /// Account and identity management.
  account,

  /// Privacy and security.
  privacy,

  /// Messaging and communication.
  messaging,

  /// Ledger and civic participation.
  ledger,

  /// War Room and incident reporting.
  warRoom,

  /// Academy and learning.
  academy,

  /// Technical and troubleshooting.
  technical,

  /// Legal and compliance.
  legal;

  /// Human-readable label.
  String get label {
    switch (this) {
      case FaqCategory.gettingStarted:
        return 'Getting Started';
      case FaqCategory.account:
        return 'Account';
      case FaqCategory.privacy:
        return 'Privacy';
      case FaqCategory.messaging:
        return 'Messaging';
      case FaqCategory.ledger:
        return 'Ledger';
      case FaqCategory.warRoom:
        return 'War Room';
      case FaqCategory.academy:
        return 'Academy';
      case FaqCategory.technical:
        return 'Technical';
      case FaqCategory.legal:
        return 'Legal';
    }
  }
}

/// Importance weighting for FAQ relevance ranking.
enum FaqRelevance {
  /// Low relevance, informational only.
  low,

  /// Standard relevance.
  medium,

  /// High relevance, commonly asked.
  high,

  /// Critical, shown at top of FAQ.
  critical;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Numeric weight for ordering.
  int get weight {
    switch (this) {
      case FaqRelevance.low:
        return 0;
      case FaqRelevance.medium:
        return 1;
      case FaqRelevance.high:
        return 2;
      case FaqRelevance.critical:
        return 3;
    }
  }
}

/// A single FAQ entry.
class FaqEntry {
  /// Unique identifier (e.g., 'FAQ-001').
  final String id;

  /// The question text.
  final String question;

  /// The answer text (may contain Markdown).
  final String answer;

  /// Category this entry belongs to.
  final FaqCategory category;

  /// Relevance / importance level.
  final FaqRelevance relevance;

  /// Search keywords for discoverability.
  final List<String> keywords;

  /// Related FAQ entry IDs.
  final List<String> relatedEntries;

  /// Number of times this entry has been marked as helpful.
  final int helpfulCount;

  /// Number of times this entry has been marked as not helpful.
  final int notHelpfulCount;

  /// Whether this entry is currently active (visible to users).
  final bool isActive;

  /// Locale code for this entry (e.g., 'en', 'hi').
  final String locale;

  const FaqEntry({
    required this.id,
    required this.question,
    required this.answer,
    this.category = FaqCategory.technical,
    this.relevance = FaqRelevance.medium,
    this.keywords = const [],
    this.relatedEntries = const [],
    this.helpfulCount = 0,
    this.notHelpfulCount = 0,
    this.isActive = true,
    this.locale = 'en',
  });

  /// Total feedback count.
  int get totalFeedbackCount => helpfulCount + notHelpfulCount;

  /// Helpfulness ratio (0.0–1.0). Returns 0.0 if no feedback.
  double get helpfulnessRatio {
    if (totalFeedbackCount == 0) return 0.0;
    return helpfulCount / totalFeedbackCount;
  }

  /// Whether this entry has received feedback.
  bool get hasFeedback => totalFeedbackCount > 0;

  /// Whether this entry is considered highly helpful (>80% positive).
  bool get isHighlyHelpful => helpfulnessRatio > 0.8 && hasFeedback;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaqEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection of FAQ entries with lookup and search capabilities.
class FaqCollection {
  /// All FAQ entries indexed by ID.
  final Map<String, FaqEntry> _entries;

  const FaqCollection({Map<String, FaqEntry> entries = const {}})
      : _entries = entries;

  /// Create an empty collection.
  factory FaqCollection.empty() => const FaqCollection();

  /// All entries.
  List<FaqEntry> get all => _entries.values.toList();

  /// Number of entries.
  int get count => _entries.length;

  /// Get entry by ID.
  FaqEntry? getById(String id) => _entries[id];

  /// Get entries by category.
  List<FaqEntry> getByCategory(FaqCategory category) =>
      _entries.values.where((e) => e.category == category).toList();

  /// Get entries by relevance.
  List<FaqEntry> getByRelevance(FaqRelevance relevance) =>
      _entries.values.where((e) => e.relevance == relevance).toList();

  /// Get only active entries.
  List<FaqEntry> get active =>
      _entries.values.where((e) => e.isActive).toList();

  /// Get entries matching a keyword search (case-insensitive).
  List<FaqEntry> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _entries.values.where((e) {
      if (e.question.toLowerCase().contains(lowerQuery)) return true;
      if (e.answer.toLowerCase().contains(lowerQuery)) return true;
      return e.keywords.any((k) => k.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Get critical entries.
  List<FaqEntry> get criticalEntries =>
      getByRelevance(FaqRelevance.critical);

  /// Categories present in this collection.
  Set<FaqCategory> get categories =>
      _entries.values.map((e) => e.category).toSet();

  /// Add an entry.
  FaqCollection withEntry(FaqEntry entry) {
    return FaqCollection(entries: Map.from(_entries)..[entry.id] = entry);
  }

  /// Remove an entry.
  FaqCollection withoutEntry(String id) {
    return FaqCollection(entries: Map.from(_entries)..remove(id));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FaqCollection &&
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
