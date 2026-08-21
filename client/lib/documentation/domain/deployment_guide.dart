/// Deployment guide domain models for operations documentation (Task 15.2).
///
/// Defines structured deployment procedures, environment configurations,
/// and release stage definitions. All values are pure — no identity, no
/// PII, no secrets, no credentials.

/// Log level for deployment environments.
enum LogLevel {
  /// Verbose debug output.
  debug,

  /// Standard operational logs.
  info,

  /// Warning messages.
  warning,

  /// Error messages only.
  error;

  /// Human-readable label.
  String get label => name[0].toUpperCase() + name.substring(1);
}

/// Target deployment environment.
enum DeploymentEnvironment {
  /// Local development.
  development,

  /// Staging / pre-production.
  staging,

  /// Production.
  production;

  /// Human-readable label.
  String get label {
    switch (this) {
      case DeploymentEnvironment.development:
        return 'Development';
      case DeploymentEnvironment.staging:
        return 'Staging';
      case DeploymentEnvironment.production:
        return 'Production';
    }
  }

  /// Whether this environment requires additional security hardening.
  bool get isHardened => this == DeploymentEnvironment.production;
}

/// A single step in a deployment procedure.
class DeploymentStep {
  /// Step number (1-indexed).
  final int number;

  /// Human-readable step title.
  final String title;

  /// Detailed description of the step.
  final String description;

  /// Expected duration of this step.
  final Duration estimatedDuration;

  /// Whether this step is mandatory (cannot be skipped).
  final bool mandatory;

  /// Pre-conditions that must be true before executing this step.
  final List<String> preconditions;

  /// Verification command to confirm the step succeeded.
  final String? verificationCommand;

  /// Rollback instruction if this step fails.
  final String? rollbackInstruction;

  const DeploymentStep({
    required this.number,
    required this.title,
    required this.description,
    this.estimatedDuration = const Duration(minutes: 5),
    this.mandatory = true,
    this.preconditions = const [],
    this.verificationCommand,
    this.rollbackInstruction,
  });

  /// Total estimated minutes.
  int get estimatedMinutes => estimatedDuration.inMinutes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentStep &&
          runtimeType == other.runtimeType &&
          number == other.number &&
          title == other.title;

  @override
  int get hashCode => Object.hash(number, title);
}

/// A complete deployment procedure for a specific environment.
class DeploymentProcedure {
  /// Unique identifier (e.g., 'deploy-production-v1').
  final String id;

  /// Human-readable name.
  final String name;

  /// Target environment.
  final DeploymentEnvironment environment;

  /// Ordered deployment steps.
  final List<DeploymentStep> steps;

  /// Prerequisites (e.g., 'Database migration completed').
  final List<String> prerequisites;

  /// Estimated total duration.
  final Duration estimatedTotalDuration;

  /// Whether this procedure requires approval before execution.
  final bool requiresApproval;

  const DeploymentProcedure({
    required this.id,
    required this.name,
    required this.environment,
    required this.steps,
    this.prerequisites = const [],
    this.estimatedTotalDuration = const Duration(minutes: 30),
    this.requiresApproval = false,
  });

  /// Number of mandatory steps.
  int get mandatoryStepCount => steps.where((s) => s.mandatory).length;

  /// Whether all steps are mandatory.
  bool get allStepsMandatory => mandatoryStepCount == steps.length;

  /// Steps that have verification commands.
  List<DeploymentStep> get verifiableSteps =>
      steps.where((s) => s.verificationCommand != null).toList();

  /// Steps that can be rolled back.
  List<DeploymentStep> get rollbackableSteps =>
      steps.where((s) => s.rollbackInstruction != null).toList();

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentProcedure &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;
}

/// Environment-specific configuration for a deployment.
class EnvironmentConfig {
  /// Target environment.
  final DeploymentEnvironment environment;

  /// Feature toggles active in this environment.
  final Map<String, bool> featureToggles;

  /// Infrastructure tier (e.g., 'small', 'medium', 'large').
  final String infrastructureTier;

  /// Minimum replica count.
  final int minReplicas;

  /// Maximum replica count.
  final int maxReplicas;

  /// Log level for this environment.
  final LogLevel logLevel;

  /// Whether analytics collection is enabled (must be false for zero-PII).
  final bool analyticsEnabled;

  /// Whether debug mode is active (must be false for production).
  final bool debugMode;

  const EnvironmentConfig({
    required this.environment,
    this.featureToggles = const {},
    this.infrastructureTier = 'medium',
    this.minReplicas = 1,
    this.maxReplicas = 3,
    this.logLevel = LogLevel.info,
    this.analyticsEnabled = false,
    this.debugMode = false,
  });

  /// Whether this config is production-safe (analytics off, debug off).
  bool get isProductionSafe => !analyticsEnabled && !debugMode;

  /// Whether this config violates zero-PII policy.
  /// Returns true if analytics is enabled or debug mode is active in production.
  bool get violatesZeroPiiPolicy => analyticsEnabled || debugMode;

  /// Number of active feature toggles.
  int get activeToggleCount =>
      featureToggles.values.where((v) => v).length;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EnvironmentConfig &&
          runtimeType == other.runtimeType &&
          environment == other.environment;

  @override
  int get hashCode => environment.hashCode;
}
