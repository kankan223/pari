/// Privacy policy domain models for end-user documentation (Task 15.3).
///
/// Defines structured privacy policy content: data categories, retention
/// periods, consent mechanisms, and user rights. All values are pure —
/// no identity, no PII, no secrets.

/// Category of data processed by the application.
enum DataCategory {
  /// Device-generated identifiers (blind hashes).
  deviceIdentifiers,

  /// Encrypted message content.
  messageContent,

  /// Civic participation posts (ledger).
  civicPosts,

  /// War Room evidence and reports.
  evidenceData,

  /// Academy learning progress.
  learningProgress,

  /// Application usage telemetry (opt-in only).
  usageTelemetry,

  /// Device metadata (OS version, screen size).
  deviceMetadata;

  /// Human-readable label.
  String get label {
    switch (this) {
      case DataCategory.deviceIdentifiers:
        return 'Device Identifiers';
      case DataCategory.messageContent:
        return 'Message Content';
      case DataCategory.civicPosts:
        return 'Civic Posts';
      case DataCategory.evidenceData:
        return 'Evidence Data';
      case DataCategory.learningProgress:
        return 'Learning Progress';
      case DataCategory.usageTelemetry:
        return 'Usage Telemetry';
      case DataCategory.deviceMetadata:
        return 'Device Metadata';
    }
  }

  /// Description of how this data is handled.
  String get description {
    switch (this) {
      case DataCategory.deviceIdentifiers:
        return 'Blind-hashed identifiers used for account recognition.';
      case DataCategory.messageContent:
        return 'End-to-end encrypted messages stored on device only.';
      case DataCategory.civicPosts:
        return 'Community posts stored encrypted at rest.';
      case DataCategory.evidenceData:
        return 'Evidence files encrypted with per-file keys.';
      case DataCategory.learningProgress:
        return 'Course progress stored locally on device.';
      case DataCategory.usageTelemetry:
        return 'Optional, anonymized usage data (opt-in only).';
      case DataCategory.deviceMetadata:
        return 'Basic device info for compatibility.';
    }
  }
}

/// Legal basis for data processing under DPDP/privacy law.
enum ProcessingBasis {
  /// Required for core service functionality.
  legitimateInterest,

  /// Explicit user consent obtained.
  consent,

  /// Required by legal obligation.
  legalObligation,

  /// Necessary for contract performance.
  contractual;

  /// Human-readable label.
  String get label {
    switch (this) {
      case ProcessingBasis.legitimateInterest:
        return 'Legitimate Interest';
      case ProcessingBasis.consent:
        return 'Consent';
      case ProcessingBasis.legalObligation:
        return 'Legal Obligation';
      case ProcessingBasis.contractual:
        return 'Contractual Necessity';
    }
  }
}

/// Data retention period definition.
class RetentionPeriod {
  /// Data category this retention applies to.
  final DataCategory dataCategory;

  /// Human-readable description of the retention period.
  final String description;

  /// Duration in days. -1 means indefinite (until user deletion).
  final int durationDays;

  /// Whether the user can request early deletion.
  final bool userDeletable;

  /// Whether this data is automatically purged.
  final bool autoPurge;

  const RetentionPeriod({
    required this.dataCategory,
    required this.description,
    this.durationDays = -1,
    this.userDeletable = true,
    this.autoPurge = false,
  });

  /// Whether retention is indefinite.
  bool get isIndefinite => durationDays < 0;

  /// Whether retention is less than 30 days.
  bool get isShortTerm => durationDays > 0 && durationDays <= 30;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RetentionPeriod &&
          runtimeType == other.runtimeType &&
          dataCategory == other.dataCategory;

  @override
  int get hashCode => dataCategory.hashCode;
}

/// A user right under privacy regulations.
class PrivacyRight {
  /// Unique identifier (e.g., 'right-access', 'right-deletion').
  final String id;

  /// Right name (e.g., 'Right to Access').
  final String name;

  /// Description of the right.
  final String description;

  /// How to exercise this right (instructions).
  final String exerciseInstructions;

  /// Expected response time in days.
  final int responseTimeDays;

  /// Whether this right can be exercised automatically.
  final bool automated;

  const PrivacyRight({
    required this.id,
    required this.name,
    required this.description,
    required this.exerciseInstructions,
    this.responseTimeDays = 30,
    this.automated = false,
  });

  /// Expected response time as a human-readable string.
  String get responseTimeLabel => '$responseTimeDays days';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacyRight &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// A clause in the privacy policy.
class PolicyClause {
  /// Clause number (e.g., '3.1').
  final String number;

  /// Clause title.
  final String title;

  /// Clause content text.
  final String content;

  /// Related data categories.
  final List<DataCategory> relatedDataCategories;

  const PolicyClause({
    required this.number,
    required this.title,
    required this.content,
    this.relatedDataCategories = const [],
  });

  /// Whether this clause relates to a specific data category.
  bool relatesTo(DataCategory category) =>
      relatedDataCategories.contains(category);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PolicyClause &&
          runtimeType == other.runtimeType &&
          number == other.number;

  @override
  int get hashCode => number.hashCode;
}

/// Complete privacy policy for the application.
class PrivacyPolicy {
  /// Application name.
  final String appName;

  /// Policy version.
  final String version;

  /// Effective date (ISO 8601).
  final String effectiveDate;

  /// Last updated date (ISO 8601).
  final String lastUpdated;

  /// Policy clauses (ordered).
  final List<PolicyClause> clauses;

  /// Data retention periods.
  final List<RetentionPeriod> retentionPeriods;

  /// User rights.
  final List<PrivacyRight> rights;

  /// Contact email for privacy inquiries (role-based, not personal).
  final String privacyContactEmail;

  /// Applicable regulations.
  final List<String> applicableRegulations;

  const PrivacyPolicy({
    required this.appName,
    required this.version,
    required this.effectiveDate,
    required this.lastUpdated,
    this.clauses = const [],
    this.retentionPeriods = const [],
    this.rights = const [],
    this.privacyContactEmail = 'privacy@civiccommons.org',
    this.applicableRegulations = const ['DPDP Act 2023'],
  });

  /// Total number of clauses.
  int get clauseCount => clauses.length;

  /// Total number of data categories covered.
  int get coveredDataCategories =>
      retentionPeriods.map((r) => r.dataCategory).toSet().length;

  /// Total number of user rights defined.
  int get rightsCount => rights.length;

  /// Get retention period for a data category.
  RetentionPeriod? getRetentionFor(DataCategory category) {
    for (final rp in retentionPeriods) {
      if (rp.dataCategory == category) return rp;
    }
    return null;
  }

  /// Get clause by number.
  PolicyClause? getClause(String number) {
    for (final c in clauses) {
      if (c.number == number) return c;
    }
    return null;
  }

  /// Get user right by ID.
  PrivacyRight? getRight(String id) {
    for (final r in rights) {
      if (r.id == id) return r;
    }
    return null;
  }

  /// Whether a specific data category requires consent.
  /// Evidence data and usage telemetry always require consent regardless
  /// of whether a retention period is defined.
  bool requiresConsent(DataCategory category) {
    if (category == DataCategory.evidenceData ||
        category == DataCategory.usageTelemetry) {
      return true;
    }
    final rp = getRetentionFor(category);
    return rp != null && rp.dataCategory == category;
  }

  /// Data categories with indefinite retention.
  List<DataCategory> get indefiniteRetention =>
      retentionPeriods
          .where((rp) => rp.isIndefinite)
          .map((rp) => rp.dataCategory)
          .toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PrivacyPolicy &&
          runtimeType == other.runtimeType &&
          appName == other.appName &&
          version == other.version;

  @override
  int get hashCode => Object.hash(appName, version);
}
