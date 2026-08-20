/// Code documentation standards domain models (Task 15.1).
///
/// Defines documentation conventions for Dart/Flutter and Go codebases.
/// All values are pure — no identity, no PII, no secrets.

/// Documentation format for a language.
enum DocFormat {
  /// Dart/Flutter style (/// doc comments).
  dartDoc,

  /// Go style (// godoc comments).
  goDoc,

  /// Markdown style.
  markdown;

  /// Human-readable label.
  String get label {
    switch (this) {
      case DocFormat.dartDoc:
        return 'Dart Doc';
      case DocFormat.goDoc:
        return 'Go Doc';
      case DocFormat.markdown:
        return 'Markdown';
    }
  }
}

/// A documentation requirement for a code element.
class DocRequirement {
  /// Code element type (e.g., 'class', 'function', 'enum').
  final String elementType;

  /// Whether documentation is required.
  final bool required;

  /// Required documentation sections.
  final List<String> sections;

  /// Example of compliant documentation.
  final String? example;

  const DocRequirement({
    required this.elementType,
    this.required = true,
    this.sections = const [],
    this.example,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocRequirement &&
          runtimeType == other.runtimeType &&
          elementType == other.elementType;

  @override
  int get hashCode => elementType.hashCode;
}

/// Complete documentation standard for a project.
class DocStandard {
  /// Project name.
  final String projectName;

  /// Documentation format.
  final DocFormat format;

  /// Minimum documentation coverage percentage.
  final int minCoveragePercent;

  /// Documentation requirements per element type.
  final List<DocRequirement> requirements;

  /// Whether API reference docs are auto-generated.
  final bool autoGenerateApiDocs;

  /// Tool used for auto-generation (e.g., 'dartdoc', 'godoc').
  final String? generationTool;

  /// Maximum line length for documentation comments.
  final int maxLineLength;

  const DocStandard({
    required this.projectName,
    this.format = DocFormat.dartDoc,
    this.minCoveragePercent = 80,
    this.requirements = const [],
    this.autoGenerateApiDocs = true,
    this.generationTool,
    this.maxLineLength = 80,
  });

  /// Get requirement for a specific element type.
  DocRequirement? requirementFor(String elementType) {
    for (final r in requirements) {
      if (r.elementType == elementType) return r;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DocStandard &&
          runtimeType == other.runtimeType &&
          projectName == other.projectName &&
          format == other.format;

  @override
  int get hashCode => Object.hash(projectName, format);
}
