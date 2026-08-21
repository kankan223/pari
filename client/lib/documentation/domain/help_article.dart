/// Help article domain models for end-user documentation (Task 15.3).
///
/// Defines structured help articles: step-by-step guides, how-tos,
/// and contextual help content. All values are pure — no identity,
/// no PII, no secrets.

/// Category for help articles.
enum ArticleCategory {
  /// Account setup and profile management.
  accountSetup,

  /// Using the messaging system.
  messaging,

  /// Civic participation and ledger posts.
  civicParticipation,

  /// Security and privacy features.
  security,

  /// War Room reporting and evidence.
  warRoom,

  /// Academy learning and courses.
  academy,

  /// Notifications and settings.
  settings,

  /// Accessibility and localization.
  accessibility;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ArticleCategory.accountSetup:
        return 'Account Setup';
      case ArticleCategory.messaging:
        return 'Messaging';
      case ArticleCategory.civicParticipation:
        return 'Civic Participation';
      case ArticleCategory.security:
        return 'Security';
      case ArticleCategory.warRoom:
        return 'War Room';
      case ArticleCategory.academy:
        return 'Academy';
      case ArticleCategory.settings:
        return 'Settings';
      case ArticleCategory.accessibility:
        return 'Accessibility';
    }
  }
}

/// Target audience for a help article.
enum ArticleAudience {
  /// General users.
  general,

  /// Users needing accessibility support.
  accessibility,

  /// Users in low-bandwidth environments.
  lowBandwidth,

  /// Users with advanced technical knowledge.
  technical;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ArticleAudience.general:
        return 'General';
      case ArticleAudience.accessibility:
        return 'Accessibility';
      case ArticleAudience.lowBandwidth:
        return 'Low Bandwidth';
      case ArticleAudience.technical:
        return 'Technical';
    }
  }
}

/// A single step in a how-to article.
class HowToStep {
  /// Step number (1-indexed).
  final int number;

  /// Step title / action verb.
  final String title;

  /// Detailed instructions.
  final String instructions;

  /// Optional screenshot or image reference (asset path, not URL).
  final String? screenshotAsset;

  /// Tip or note for this step.
  final String? tip;

  const HowToStep({
    required this.number,
    required this.title,
    required this.instructions,
    this.screenshotAsset,
    this.tip,
  });

  /// Whether this step includes a visual aid.
  bool get hasVisualAid => screenshotAsset != null;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HowToStep &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          title == other.title;

  @override
  int get hashCode => Object.hash(number, title);
}

/// A single help article.
class HelpArticle {
  /// Unique identifier (e.g., 'HELP-001').
  final String id;

  /// Article title.
  final String title;

  /// Brief summary for previews.
  final String summary;

  /// Full article content (Markdown).
  final String content;

  /// Category.
  final ArticleCategory category;

  /// Target audience.
  final ArticleAudience audience;

  /// Estimated reading time in minutes.
  final int readingTimeMinutes;

  /// How-to steps (null if article is not a how-to).
  final List<HowToStep>? steps;

  /// Search keywords for discoverability.
  final List<String> keywords;

  /// Related article IDs.
  final List<String> relatedArticles;

  /// Whether this article is currently published.
  final bool isPublished;

  /// Locale code (e.g., 'en', 'hi').
  final String locale;

  /// Version of the article content.
  final int contentVersion;

  const HelpArticle({
    required this.id,
    required this.title,
    required this.summary,
    required this.content,
    this.category = ArticleCategory.accountSetup,
    this.audience = ArticleAudience.general,
    this.readingTimeMinutes = 5,
    this.steps,
    this.keywords = const [],
    this.relatedArticles = const [],
    this.isPublished = true,
    this.locale = 'en',
    this.contentVersion = 1,
  });

  /// Whether this article is a how-to guide with steps.
  bool get isHowTo => steps != null && steps!.isNotEmpty;

  /// Number of steps (0 if not a how-to).
  int get stepCount => steps?.length ?? 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HelpArticle &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection of help articles with lookup and search capabilities.
class HelpArticleCollection {
  /// All articles indexed by ID.
  final Map<String, HelpArticle> _articles;

  const HelpArticleCollection({Map<String, HelpArticle> articles = const {}})
      : _articles = articles;

  /// Create an empty collection.
  factory HelpArticleCollection.empty() => const HelpArticleCollection();

  /// All articles.
  List<HelpArticle> get all => _articles.values.toList();

  /// Number of articles.
  int get count => _articles.length;

  /// Get article by ID.
  HelpArticle? getById(String id) => _articles[id];

  /// Get articles by category.
  List<HelpArticle> getByCategory(ArticleCategory category) =>
      _articles.values.where((a) => a.category == category).toList();

  /// Get articles by audience.
  List<HelpArticle> getByAudience(ArticleAudience audience) =>
      _articles.values.where((a) => a.audience == audience).toList();

  /// Get only published articles.
  List<HelpArticle> get published =>
      _articles.values.where((a) => a.isPublished).toList();

  /// Search articles by keyword (case-insensitive).
  List<HelpArticle> search(String query) {
    final lowerQuery = query.toLowerCase();
    return _articles.values.where((a) {
      if (a.title.toLowerCase().contains(lowerQuery)) return true;
      if (a.summary.toLowerCase().contains(lowerQuery)) return true;
      if (a.content.toLowerCase().contains(lowerQuery)) return true;
      return a.keywords.any((k) => k.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// Get only how-to articles.
  List<HelpArticle> get howToArticles =>
      _articles.values.where((a) => a.isHowTo).toList();

  /// Categories present in this collection.
  Set<ArticleCategory> get categories =>
      _articles.values.map((a) => a.category).toSet();

  /// Add an article.
  HelpArticleCollection withArticle(HelpArticle article) {
    return HelpArticleCollection(
        articles: Map.from(_articles)..[article.id] = article);
  }

  /// Remove an article.
  HelpArticleCollection withoutArticle(String id) {
    return HelpArticleCollection(articles: Map.from(_articles)..remove(id));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HelpArticleCollection &&
          runtimeType == other.runtimeType &&
          _mapEquals(_articles, other._articles);

  @override
  int get hashCode => Object.hashAll(
      _articles.entries.map((e) => Object.hash(e.key, e.value)));

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
