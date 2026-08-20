/// Contributor guidelines domain models (Task 15.1).
///
/// Defines the standards and conventions for contributing to the Civic Commons
/// codebase. All values are pure — no identity, no PII, no secrets.

/// Types of contributions allowed.
enum ContributionType {
  /// Bug fix.
  bugFix,

  /// New feature.
  feature,

  /// Documentation update.
  documentation,

  /// Refactoring (no behavior change).
  refactor,

  /// Test addition or improvement.
  testing,

  /// Security fix.
  securityFix;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ContributionType.bugFix:
        return 'Bug Fix';
      case ContributionType.feature:
        return 'Feature';
      case ContributionType.documentation:
        return 'Documentation';
      case ContributionType.refactor:
        return 'Refactoring';
      case ContributionType.testing:
        return 'Testing';
      case ContributionType.securityFix:
        return 'Security Fix';
    }
  }

  /// Conventional commit prefix.
  String get commitPrefix {
    switch (this) {
      case ContributionType.bugFix:
        return 'fix';
      case ContributionType.feature:
        return 'feat';
      case ContributionType.documentation:
        return 'docs';
      case ContributionType.refactor:
        return 'refactor';
      case ContributionType.testing:
        return 'test';
      case ContributionType.securityFix:
        return 'fix(security)';
    }
  }
}

/// Code review requirement level.
enum ReviewRequirement {
  /// No review required.
  none,

  /// One reviewer required.
  single,

  /// Two reviewers required.
  twoReviewers,

  /// Security team review required.
  securityReview;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ReviewRequirement.none:
        return 'No Review';
      case ReviewRequirement.single:
        return '1 Reviewer';
      case ReviewRequirement.twoReviewers:
        return '2 Reviewers';
      case ReviewRequirement.securityReview:
        return 'Security Review';
    }
  }
}

/// A coding standard or convention.
class CodingStandard {
  /// Standard name.
  final String name;

  /// Description of the standard.
  final String description;

  /// Example of correct usage.
  final String? example;

  /// Anti-pattern to avoid.
  final String? antiPattern;

  /// Whether this standard is enforced by linting.
  final bool enforcedByLinter;

  const CodingStandard({
    required this.name,
    required this.description,
    this.example,
    this.antiPattern,
    this.enforcedByLinter = false,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CodingStandard &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

/// Complete contributor guidelines.
class ContributorGuidelines {
  /// Project name.
  final String projectName;

  /// Minimum Flutter SDK version.
  final String minFlutterVersion;

  /// Minimum Dart SDK version.
  final String minDartVersion;

  /// Required code formatting tool.
  final String formatter;

  /// Required static analysis tool.
  final String linter;

  /// Minimum test coverage percentage.
  final int minCoveragePercent;

  /// Commit message format.
  final String commitFormat;

  /// Branch naming convention.
  final String branchConvention;

  /// PR title convention.
  final String prTitleConvention;

  /// Coding standards.
  final List<CodingStandard> standards;

  /// Review requirements per contribution type.
  final Map<ContributionType, ReviewRequirement> reviewRequirements;

  const ContributorGuidelines({
    required this.projectName,
    this.minFlutterVersion = '3.19.0',
    this.minDartVersion = '3.3.0',
    this.formatter = 'dart format',
    this.linter = 'flutter analyze',
    this.minCoveragePercent = 80,
    this.commitFormat = 'conventional',
    this.branchConvention = 'feature/TICKET-description',
    this.prTitleConvention = 'type(scope): description',
    this.standards = const [],
    this.reviewRequirements = const {},
  });

  /// Get review requirement for a contribution type.
  ReviewRequirement reviewFor(ContributionType type) =>
      reviewRequirements[type] ?? ReviewRequirement.single;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ContributorGuidelines &&
          runtimeType == other.runtimeType &&
          projectName == other.projectName;

  @override
  int get hashCode => projectName.hashCode;
}
