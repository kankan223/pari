/// Bug bounty program domain models for handover documentation (Task 15.4).
///
/// Defines structured bug bounty program documentation: scope, rules,
/// reward tiers, submission guidelines, and safe harbor provisions.
/// All values are pure — no identity, no PII, no secrets, no credentials.

/// Reward tier for a bug bounty finding.
enum BountyRewardTier {
  /// Low-impact finding.
  low,

  /// Medium-impact finding.
  medium,

  /// High-impact finding.
  high,

  /// Critical-impact finding.
  critical;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);

  /// Numeric weight for ordering.
  int get weight {
    switch (this) {
      case BountyRewardTier.low:
        return 0;
      case BountyRewardTier.medium:
        return 1;
      case BountyRewardTier.high:
        return 2;
      case BountyRewardTier.critical:
        return 3;
    }
  }

  /// Human-readable reward range description.
  String get rewardRange {
    switch (this) {
      case BountyRewardTier.low:
        return 'Low reward';
      case BountyRewardTier.medium:
        return 'Medium reward';
      case BountyRewardTier.high:
        return 'High reward';
      case BountyRewardTier.critical:
        return 'Critical reward';
    }
  }
}

/// Status of a bug bounty submission.
enum BountySubmissionStatus {
  /// Newly submitted.
  submitted,

  /// Under review by security team.
  underReview,

  /// Confirmed as valid.
  confirmed,

  /// Fix in progress.
  fixInProgress,

  /// Fix deployed.
  fixDeployed,

  /// Reward issued.
  rewardIssued,

  /// Submission rejected.
  rejected,

  /// Duplicate of existing report.
  duplicate;

  /// Human-readable label.
  String get label {
    switch (this) {
      case BountySubmissionStatus.submitted:
        return 'Submitted';
      case BountySubmissionStatus.underReview:
        return 'Under Review';
      case BountySubmissionStatus.confirmed:
        return 'Confirmed';
      case BountySubmissionStatus.fixInProgress:
        return 'Fix In Progress';
      case BountySubmissionStatus.fixDeployed:
        return 'Fix Deployed';
      case BountySubmissionStatus.rewardIssued:
        return 'Reward Issued';
      case BountySubmissionStatus.rejected:
        return 'Rejected';
      case BountySubmissionStatus.duplicate:
        return 'Duplicate';
    }
  }
}

/// Scope definition for the bug bounty program.
class BountyScope {
  /// In-scope components or areas.
  final List<String> inScope;

  /// Out-of-scope components or areas.
  final List<String> outOfScope;

  /// Allowed testing methods.
  final List<String> allowedMethods;

  /// Prohibited testing methods.
  final List<String> prohibitedMethods;

  const BountyScope({
    this.inScope = const [],
    this.outOfScope = const [],
    this.allowedMethods = const [],
    this.prohibitedMethods = const [],
  });

  /// Whether a component is in scope.
  bool isInScope(String component) =>
      inScope.any((s) => component.toLowerCase().contains(s.toLowerCase()));

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is BountyScope && runtimeType == other.runtimeType;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// A bug bounty submission.
class BountySubmission {
  /// Unique identifier (e.g., 'BB-2026-001').
  final String id;

  /// Vulnerability title.
  final String title;

  /// Description of the vulnerability.
  final String description;

  /// Affected component.
  final String affectedComponent;

  /// Severity assessment.
  final BountyRewardTier severity;

  /// Current status.
  final BountySubmissionStatus status;

  /// Submission date (ISO 8601).
  final String submittedDate;

  /// Reporter handle (blinded, not personal identity).
  final String reporterHandle;

  /// Steps to reproduce.
  final String stepsToReproduce;

  /// Suggested fix or mitigation.
  final String? suggestedFix;

  /// Date of last status update (ISO 8601).
  final String? lastUpdated;

  const BountySubmission({
    required this.id,
    required this.title,
    required this.description,
    required this.affectedComponent,
    required this.severity,
    this.status = BountySubmissionStatus.submitted,
    required this.submittedDate,
    required this.reporterHandle,
    required this.stepsToReproduce,
    this.suggestedFix,
    this.lastUpdated,
  });

  /// Whether this submission has been accepted (confirmed or beyond).
  bool get isAccepted =>
      status == BountySubmissionStatus.confirmed ||
      status == BountySubmissionStatus.fixInProgress ||
      status == BountySubmissionStatus.fixDeployed ||
      status == BountySubmissionStatus.rewardIssued;

  /// Whether this submission has been rejected.
  bool get isRejected =>
      status == BountySubmissionStatus.rejected ||
      status == BountySubmissionStatus.duplicate;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BountySubmission &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Complete bug bounty program documentation.
class BugBountyProgram {
  /// Program name.
  final String programName;

  /// Program version.
  final String version;

  /// Program description.
  final String description;

  /// Scope of the program.
  final BountyScope scope;

  /// Reward tiers and descriptions.
  final List<BountyRewardTier> rewardTiers;

  /// Submission guidelines.
  final List<String> submissionGuidelines;

  /// Safe harbor provisions.
  final List<String> safeHarborProvisions;

  /// Expected response times in days.
  final int acknowledgmentDays;

  /// Triage time in days.
  final int triageDays;

  /// Fix time for critical findings in days.
  final int criticalFixDays;

  /// Contact email (role-based, not personal).
  final String contactEmail;

  /// Whether the program is currently active.
  final bool isActive;

  const BugBountyProgram({
    required this.programName,
    required this.version,
    required this.description,
    this.scope = const BountyScope(),
    this.rewardTiers = const [],
    this.submissionGuidelines = const [],
    this.safeHarborProvisions = const [],
    this.acknowledgmentDays = 3,
    this.triageDays = 7,
    this.criticalFixDays = 30,
    this.contactEmail = 'security@civiccommons.org',
    this.isActive = true,
  });

  /// Number of submission guidelines.
  int get guidelineCount => submissionGuidelines.length;

  /// Number of safe harbor provisions.
  int get safeHarborCount => safeHarborProvisions.length;

  /// Whether a specific testing method is allowed.
  bool isMethodAllowed(String method) =>
      scope.allowedMethods
          .any((m) => method.toLowerCase().contains(m.toLowerCase())) &&
      !scope.prohibitedMethods
          .any((m) => method.toLowerCase().contains(m.toLowerCase()));

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BugBountyProgram &&
          runtimeType == other.runtimeType &&
          programName == other.programName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(programName, version);
}
