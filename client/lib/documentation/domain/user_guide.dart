/// End-user User Guide domain models for documentation (Task 15.3).
///
/// Defines structured user guide content: chapters, sections, and
/// navigation aids for the Civic Commons application. All values are
/// pure — no identity, no PII, no secrets.

/// Target audience for a user guide section.
enum GuideAudience {
  /// First-time users.
  newUsers,

  /// Returning users.
  returningUsers,

  /// Power users / advanced features.
  advancedUsers,

  /// Administrators / moderators.
  administrators;

  /// Human-readable label.
  String get label {
    switch (this) {
      case GuideAudience.newUsers:
        return 'New Users';
      case GuideAudience.returningUsers:
        return 'Returning Users';
      case GuideAudience.advancedUsers:
        return 'Advanced Users';
      case GuideAudience.administrators:
        return 'Administrators';
    }
  }
}

/// Difficulty level for a guide section.
enum DifficultyLevel {
  /// Beginner-friendly.
  beginner,

  /// Intermediate knowledge required.
  intermediate,

  /// Advanced / expert topics.
  advanced;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Numeric weight for ordering.
  int get weight {
    switch (this) {
      case DifficultyLevel.beginner:
        return 0;
      case DifficultyLevel.intermediate:
        return 1;
      case DifficultyLevel.advanced:
        return 2;
    }
  }
}

/// A single section within a user guide chapter.
class GuideSection {
  /// Unique identifier (e.g., 'getting-started-otp').
  final String id;

  /// Section title.
  final String title;

  /// Markdown content body.
  final String content;

  /// Target audience.
  final GuideAudience audience;

  /// Difficulty level.
  final DifficultyLevel difficulty;

  /// Estimated reading time in minutes.
  final int readingTimeMinutes;

  /// Ordered list of prerequisite section IDs.
  final List<String> prerequisites;

  /// Related section IDs for cross-referencing.
  final List<String> relatedSections;

  const GuideSection({
    required this.id,
    required this.title,
    required this.content,
    this.audience = GuideAudience.newUsers,
    this.difficulty = DifficultyLevel.beginner,
    this.readingTimeMinutes = 5,
    this.prerequisites = const [],
    this.relatedSections = const [],
  });

  /// Whether this section has prerequisites.
  bool get hasPrerequisites => prerequisites.isNotEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuideSection &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A chapter grouping multiple guide sections.
class GuideChapter {
  /// Chapter number (1-indexed).
  final int number;

  /// Chapter title.
  final String title;

  /// Chapter description.
  final String description;

  /// Sections within this chapter (ordered).
  final List<GuideSection> sections;

  const GuideChapter({
    required this.number,
    required this.title,
    required this.description,
    this.sections = const [],
  });

  /// Number of sections in this chapter.
  int get sectionCount => sections.length;

  /// Total reading time for all sections.
  int get totalReadingTimeMinutes =>
      sections.fold(0, (sum, s) => sum + s.readingTimeMinutes);

  /// Whether all sections are beginner-level.
  bool get allBeginner =>
      sections.every((s) => s.difficulty == DifficultyLevel.beginner);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GuideChapter &&
          runtimeType == other.runtimeType &&
          number == other.number;

  @override
  int get hashCode => number.hashCode;
}

/// Complete user guide for the application.
class UserGuide {
  /// Application name.
  final String appName;

  /// Current version of the guide.
  final String version;

  /// Last updated date (ISO 8601).
  final String lastUpdated;

  /// Ordered chapters.
  final List<GuideChapter> chapters;

  /// Supported locale codes (e.g., ['en', 'hi']).
  final List<String> locales;

  const UserGuide({
    required this.appName,
    required this.version,
    required this.lastUpdated,
    this.chapters = const [],
    this.locales = const ['en'],
  });

  /// Total number of chapters.
  int get chapterCount => chapters.length;

  /// Total number of sections across all chapters.
  int get totalSectionCount =>
      chapters.fold(0, (sum, c) => sum + c.sectionCount);

  /// Total reading time in minutes.
  int get totalReadingTimeMinutes =>
      chapters.fold(0, (sum, c) => sum + c.totalReadingTimeMinutes);

  /// Find a section by its ID across all chapters.
  GuideSection? findSection(String sectionId) {
    for (final chapter in chapters) {
      for (final section in chapter.sections) {
        if (section.id == sectionId) return section;
      }
    }
    return null;
  }

  /// Chapters filtered for a specific audience.
  List<GuideChapter> chaptersForAudience(GuideAudience audience) {
    return chapters
        .where((c) => c.sections.any((s) => s.audience == audience))
        .toList();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserGuide &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(appName, version);
}
