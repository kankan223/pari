/// Troubleshooting guide domain models for operations documentation (Task 15.2).
///
/// Defines structured diagnostic procedures, common issues, and resolution
/// steps. All values are pure — no identity, no PII, no secrets, no credentials.

import 'runbook.dart';

/// Category of troubleshooting issue.
enum IssueCategory {
  /// Database-related issues.
  database,

  /// Network and connectivity issues.
  network,

  /// Performance and latency issues.
  performance,

  /// Authentication and authorization issues.
  authentication,

  /// Storage and encryption issues.
  storage,

  /// Application crash or runtime error.
  runtime;

  /// Human-readable label.
  String get label {
    switch (this) {
      case IssueCategory.database:
        return 'Database';
      case IssueCategory.network:
        return 'Network';
      case IssueCategory.performance:
        return 'Performance';
      case IssueCategory.authentication:
        return 'Authentication';
      case IssueCategory.storage:
        return 'Storage';
      case IssueCategory.runtime:
        return 'Runtime';
    }
  }
}

/// A diagnostic step to identify the root cause.
class DiagnosticStep {
  /// Step number (1-indexed).
  final int number;

  /// Human-readable description of the check.
  final String description;

  /// Command or query to run for this diagnostic.
  final String command;

  /// Expected healthy output.
  final String expectedOutput;

  /// What an unhealthy output indicates.
  final String unhealthyIndication;

  const DiagnosticStep({
    required this.number,
    required this.description,
    required this.command,
    required this.expectedOutput,
    required this.unhealthyIndication,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DiagnosticStep &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          description == other.description;

  @override
  int get hashCode => Object.hash(number, description);
}

/// A resolution step to fix a diagnosed issue.
class ResolutionStep {
  /// Step number (1-indexed).
  final int number;

  /// Human-readable description of the resolution action.
  final String action;

  /// Detailed instructions for performing this action.
  final String details;

  /// Expected duration.
  final Duration estimatedDuration;

  /// Whether this step is reversible.
  final bool reversible;

  /// Verification command to confirm the fix.
  final String? verificationCommand;

  const ResolutionStep({
    required this.number,
    required this.action,
    required this.details,
    this.estimatedDuration = const Duration(minutes: 5),
    this.reversible = true,
    this.verificationCommand,
  });

  /// Total estimated minutes.
  int get estimatedMinutes => estimatedDuration.inMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ResolutionStep &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          action == other.action;

  @override
  int get hashCode => Object.hash(number, action);
}

/// A single known issue with its diagnostic and resolution procedure.
class TroubleshootingEntry {
  /// Unique identifier (e.g., 'TSHOOT-001').
  final String id;

  /// Short title of the issue.
  final String title;

  /// Category of the issue.
  final IssueCategory category;

  /// Severity of the issue.
  final IncidentSeverity severity;

  /// Description of the symptoms observed.
  final String symptoms;

  /// Possible root causes.
  final List<String> rootCauses;

  /// Ordered diagnostic steps.
  final List<DiagnosticStep> diagnostics;

  /// Ordered resolution steps.
  final List<ResolutionStep> resolutions;

  /// Estimated time to resolve.
  final Duration estimatedTimeToResolve;

  /// Related issue IDs.
  final List<String> relatedIssues;

  const TroubleshootingEntry({
    required this.id,
    required this.title,
    required this.category,
    required this.severity,
    required this.symptoms,
    required this.rootCauses,
    required this.diagnostics,
    required this.resolutions,
    this.estimatedTimeToResolve = const Duration(minutes: 15),
    this.relatedIssues = const [],
  });

  /// Number of diagnostic steps.
  int get diagnosticCount => diagnostics.length;

  /// Number of resolution steps.
  int get resolutionCount => resolutions.length;

  /// Total steps (diagnostic + resolution).
  int get totalStepCount => diagnosticCount + resolutionCount;

  /// Estimated minutes to resolve.
  int get estimatedMinutes => estimatedTimeToResolve.inMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TroubleshootingEntry &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A complete troubleshooting guide.
class TroubleshootingGuide {
  /// Project or system name.
  final String systemName;

  /// All known troubleshooting entries.
  final List<TroubleshootingEntry> entries;

  /// Emergency contacts (role labels only, no real identities).
  final List<String> emergencyContacts;

  const TroubleshootingGuide({
    required this.systemName,
    required this.entries,
    this.emergencyContacts = const [],
  });

  /// Number of known issues.
  int get issueCount => entries.length;

  /// Get entry by ID.
  TroubleshootingEntry? getById(String id) {
    for (final entry in entries) {
      if (entry.id == id) return entry;
    }
    return null;
  }

  /// Get entries by category.
  List<TroubleshootingEntry> getByCategory(IssueCategory category) =>
      entries.where((e) => e.category == category).toList();

  /// Get entries by severity.
  List<TroubleshootingEntry> getBySeverity(IncidentSeverity severity) =>
      entries.where((e) => e.severity == severity).toList();

  /// Categories with known issues.
  Set<IssueCategory> get affectedCategories =>
      entries.map((e) => e.category).toSet();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TroubleshootingGuide &&
          runtimeType == other.runtimeType &&
          systemName == other.systemName;

  @override
  int get hashCode => systemName.hashCode;
}
