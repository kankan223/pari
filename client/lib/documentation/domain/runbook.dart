/// Runbook domain models for operations documentation (Task 15.2).
///
/// Defines structured operational procedures for common tasks like
/// rollback, scaling, incident response, and maintenance. All values
/// are pure — no identity, no PII, no secrets, no credentials.

/// Severity level for operational incidents.
enum IncidentSeverity {
  /// System is fully operational.
  informational,

  /// Minor degradation, workaround available.
  low,

  /// Partial system degradation.
  medium,

  /// Major service disruption.
  high,

  /// Complete system outage.
  critical;

  /// Human-readable label.
  String get label {
    switch (this) {
      case IncidentSeverity.informational:
        return 'Informational';
      case IncidentSeverity.low:
        return 'Low';
      case IncidentSeverity.medium:
        return 'Medium';
      case IncidentSeverity.high:
        return 'High';
      case IncidentSeverity.critical:
        return 'Critical';
    }
  }

  /// Numeric weight for severity ordering.
  int get weight {
    switch (this) {
      case IncidentSeverity.informational:
        return 0;
      case IncidentSeverity.low:
        return 1;
      case IncidentSeverity.medium:
        return 2;
      case IncidentSeverity.high:
        return 3;
      case IncidentSeverity.critical:
        return 4;
    }
  }
}

/// Category of operational runbook.
enum RunbookCategory {
  /// Rollback and recovery procedures.
  rollback,

  /// Horizontal scaling procedures.
  scaling,

  /// Incident response procedures.
  incidentResponse,

  /// Database maintenance procedures.
  databaseMaintenance,

  /// Certificate and secrets rotation.
  certificateRotation,

  /// Performance degradation response.
  performanceDegradation;

  /// Human-readable label.
  String get label {
    switch (this) {
      case RunbookCategory.rollback:
        return 'Rollback';
      case RunbookCategory.scaling:
        return 'Scaling';
      case RunbookCategory.incidentResponse:
        return 'Incident Response';
      case RunbookCategory.databaseMaintenance:
        return 'Database Maintenance';
      case RunbookCategory.certificateRotation:
        return 'Certificate Rotation';
      case RunbookCategory.performanceDegradation:
        return 'Performance Degradation';
    }
  }
}

/// A single step in an operational runbook.
class RunbookStep {
  /// Step number (1-indexed).
  final int number;

  /// Human-readable step title.
  final String title;

  /// Detailed description of the action to take.
  final String action;

  /// Expected duration of this step.
  final Duration estimatedDuration;

  /// Whether this step requires manual intervention.
  final bool requiresManualIntervention;

  /// Verification command to confirm success.
  final String? verificationCommand;

  /// What to do if this step fails.
  final String? failureAction;

  /// Safety warning (e.g., 'This action is irreversible').
  final String? safetyWarning;

  const RunbookStep({
    required this.number,
    required this.title,
    required this.action,
    this.estimatedDuration = const Duration(minutes: 2),
    this.requiresManualIntervention = false,
    this.verificationCommand,
    this.failureAction,
    this.safetyWarning,
  });

  /// Total estimated minutes.
  int get estimatedMinutes => estimatedDuration.inMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunbookStep &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          title == other.title;

  @override
  int get hashCode => Object.hash(number, title);
}

/// A complete operational runbook.
class Runbook {
  /// Unique identifier (e.g., 'rb-rollout-crashloop').
  final String id;

  /// Human-readable title.
  final String title;

  /// Category of this runbook.
  final RunbookCategory category;

  /// Severity level this runbook addresses.
  final IncidentSeverity severity;

  /// Ordered steps to execute.
  final List<RunbookStep> steps;

  /// Preconditions (e.g., 'On-call engineer authenticated').
  final List<String> prerequisites;

  /// Estimated total duration.
  final Duration estimatedTotalDuration;

  /// Whether user notification is required before execution.
  final bool requiresUserNotification;

  /// Escalation contacts (role labels only, no real identities).
  final List<String> escalationContacts;

  const Runbook({
    required this.id,
    required this.title,
    required this.category,
    required this.severity,
    required this.steps,
    this.prerequisites = const [],
    this.estimatedTotalDuration = const Duration(minutes: 15),
    this.requiresUserNotification = false,
    this.escalationContacts = const [],
  });

  /// Number of steps requiring manual intervention.
  int get manualStepCount =>
      steps.where((s) => s.requiresManualIntervention).length;

  /// Whether any steps have safety warnings.
  bool get hasSafetyWarnings =>
      steps.any((s) => s.safetyWarning != null);

  /// Steps with failure fallback actions.
  List<RunbookStep> get stepsWithFallbacks =>
      steps.where((s) => s.failureAction != null).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Runbook &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A collection of runbooks indexed by category.
class RunbookIndex {
  /// All runbooks indexed by ID.
  final Map<String, Runbook> _runbooks;

  const RunbookIndex({Map<String, Runbook> runbooks = const {}})
      : _runbooks = runbooks;

  /// Create an empty index.
  factory RunbookIndex.empty() => const RunbookIndex();

  /// All runbooks.
  List<Runbook> get all => _runbooks.values.toList();

  /// Number of runbooks.
  int get count => _runbooks.length;

  /// Get runbook by ID.
  Runbook? getById(String id) => _runbooks[id];

  /// Get runbooks by category.
  List<Runbook> getByCategory(RunbookCategory category) =>
      _runbooks.values.where((r) => r.category == category).toList();

  /// Get runbooks by severity.
  List<Runbook> getBySeverity(IncidentSeverity severity) =>
      _runbooks.values.where((r) => r.severity == severity).toList();

  /// Get all critical-severity runbooks.
  List<Runbook> get criticalRunbooks =>
      getBySeverity(IncidentSeverity.critical);

  /// Add a runbook.
  RunbookIndex withRunbook(Runbook runbook) {
    return RunbookIndex(runbooks: Map.from(_runbooks)..[runbook.id] = runbook);
  }

  /// Remove a runbook.
  RunbookIndex withoutRunbook(String id) {
    return RunbookIndex(runbooks: Map.from(_runbooks)..remove(id));
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RunbookIndex &&
          runtimeType == other.runtimeType &&
          _mapEquals(_runbooks, other._runbooks);

  @override
  int get hashCode => Object.hashAll(
      _runbooks.entries.map((e) => Object.hash(e.key, e.value)));

  static bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) {
    if (a.length != b.length) return false;
    for (final key in a.keys) {
      if (a[key] != b[key]) return false;
    }
    return true;
  }
}
