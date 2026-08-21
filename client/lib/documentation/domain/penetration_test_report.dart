/// Penetration test report domain models for handover documentation (Task 15.4).
///
/// Defines structured penetration test findings, severity classifications,
/// and remediation tracking. All values are pure — no identity, no PII,
/// no secrets, no credentials.

/// Severity of a penetration test finding.
enum PentestSeverity {
  /// Informational observation.
  informational,

  /// Low-risk finding.
  low,

  /// Medium-risk finding.
  medium,

  /// High-risk finding.
  high,

  /// Critical vulnerability.
  critical;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Numeric weight for ordering.
  int get weight {
    switch (this) {
      case PentestSeverity.informational:
        return 0;
      case PentestSeverity.low:
        return 1;
      case PentestSeverity.medium:
        return 2;
      case PentestSeverity.high:
        return 3;
      case PentestSeverity.critical:
        return 4;
    }
  }
}

/// Status of a penetration test finding.
enum FindingStatus {
  /// Newly discovered.
  open,

  /// Fix in progress.
  inProgress,

  /// Fix implemented, pending verification.
  fixPendingVerification,

  /// Verified fixed.
  resolved,

  /// Accepted as risk, no fix planned.
  acceptedRisk,

  /// False positive.
  falsePositive;

  /// Human-readable label.
  String get label {
    switch (this) {
      case FindingStatus.open:
        return 'Open';
      case FindingStatus.inProgress:
        return 'In Progress';
      case FindingStatus.fixPendingVerification:
        return 'Fix Pending Verification';
      case FindingStatus.resolved:
        return 'Resolved';
      case FindingStatus.acceptedRisk:
        return 'Accepted Risk';
      case FindingStatus.falsePositive:
        return 'False Positive';
    }
  }
}

/// A single penetration test finding.
class PentestFinding {
  /// Unique identifier (e.g., 'PTF-001').
  final String id;

  /// Finding title.
  final String title;

  /// Description of the vulnerability.
  final String description;

  /// Severity classification.
  final PentestSeverity severity;

  /// Current status.
  final FindingStatus status;

  /// Affected component or module.
  final String affectedComponent;

  /// Steps to reproduce.
  final String stepsToReproduce;

  /// Remediation recommendation.
  final String remediation;

  /// OWASP category (e.g., 'MASVS-NETWORK').
  final String owaspCategory;

  /// Date discovered (ISO 8601).
  final String discoveredDate;

  /// Date resolved (ISO 8601), null if unresolved.
  final String? resolvedDate;

  /// Tester role (not personal identity).
  final String testerRole;

  const PentestFinding({
    required this.id,
    required this.title,
    required this.description,
    required this.severity,
    this.status = FindingStatus.open,
    required this.affectedComponent,
    required this.stepsToReproduce,
    required this.remediation,
    this.owaspCategory = '',
    required this.discoveredDate,
    this.resolvedDate,
    this.testerRole = 'Security Team',
  });

  /// Whether this finding is resolved or accepted.
  bool get isClosed =>
      status == FindingStatus.resolved ||
      status == FindingStatus.acceptedRisk ||
      status == FindingStatus.falsePositive;

  /// Whether this finding requires immediate attention.
  bool get requiresAttention =>
      !isClosed &&
      (severity == PentestSeverity.high || severity == PentestSeverity.critical);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PentestFinding &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A complete penetration test report.
class PentestReport {
  /// Report identifier (e.g., 'PENTEST-2026-Q3').
  final String id;

  /// Test scope description.
  final String scope;

  /// Testing methodology used.
  final String methodology;

  /// Date of test execution (ISO 8601).
  final String testDate;

  /// Tester role labels (no personal identities).
  final List<String> testerRoles;

  /// All findings.
  final List<PentestFinding> findings;

  /// Executive summary.
  final String executiveSummary;

  /// Overall risk rating.
  final PentestSeverity overallRiskRating;

  const PentestReport({
    required this.id,
    required this.scope,
    required this.methodology,
    required this.testDate,
    this.testerRoles = const ['Security Team'],
    this.findings = const [],
    this.executiveSummary = '',
    this.overallRiskRating = PentestSeverity.low,
  });

  /// Total number of findings.
  int get findingCount => findings.length;

  /// Findings by severity.
  List<PentestFinding> findBySeverity(PentestSeverity severity) =>
      findings.where((f) => f.severity == severity).toList();

  /// Open findings requiring attention.
  List<PentestFinding> get openFindings =>
      findings.where((f) => f.requiresAttention).toList();

  /// All resolved findings.
  List<PentestFinding> get resolvedFindings =>
      findings.where((f) => f.isClosed).toList();

  /// Number of critical findings.
  int get criticalCount => findBySeverity(PentestSeverity.critical).length;

  /// Number of high findings.
  int get highCount => findBySeverity(PentestSeverity.high).length;

  /// Whether all critical and high findings are resolved.
  bool get allCriticalResolved =>
      openFindings.isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PentestReport &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}
