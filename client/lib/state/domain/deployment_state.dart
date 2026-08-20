import 'package:civic_commons/deployment/domain/build_config.dart';
import 'package:civic_commons/deployment/domain/ci_cd_config.dart';
import 'package:civic_commons/deployment/domain/health_monitor.dart';
import 'package:civic_commons/deployment/domain/release_verifier.dart';

/// State for the deployment and monitoring feature (Task 14.1–14.4).
///
/// Carries only build metadata, health metrics, and verification results —
/// zero PII, zero identity.
class DeploymentState {
  /// Current build configuration.
  final EnvironmentConfig? buildConfig;

  /// CI/CD pipeline status.
  final CiCdPipeline? pipeline;

  /// Results of CI/CD pipeline stages.
  final List<StageResultRecord> stageResults;

  /// Health report from local monitoring.
  final HealthReport? healthReport;

  /// Release verification report.
  final ReleaseVerificationReport? verificationReport;

  /// Whether a build is in progress.
  final bool isBuilding;

  /// Whether verification is in progress.
  final bool isVerifying;

  /// Error message if an operation failed.
  final String? errorMessage;

  const DeploymentState({
    this.buildConfig,
    this.pipeline,
    this.stageResults = const [],
    this.healthReport,
    this.verificationReport,
    this.isBuilding = false,
    this.isVerifying = false,
    this.errorMessage,
  });

  /// Whether the build configuration is set.
  bool get hasBuildConfig => buildConfig != null;

  /// Whether the pipeline is configured.
  bool get hasPipeline => pipeline != null;

  /// Whether the health report is available.
  bool get hasHealthReport => healthReport != null;

  /// Whether the verification report is available.
  bool get hasVerificationReport => verificationReport != null;

  /// Whether all CI/CD stages passed.
  bool get allStagesPassed =>
      stageResults.every((r) => r.result.isSuccess);

  /// Whether any CI/CD stage failed.
  bool get hasStageFailures =>
      stageResults.any((r) => r.result.isFailure);

  /// Number of CI/CD stages that passed.
  int get stagesPassedCount =>
      stageResults.where((r) => r.result.isSuccess).length;

  /// Total number of CI/CD stages.
  int get stagesTotalCount => stageResults.length;

  /// Whether the release verification passed.
  bool get verificationPassed =>
      verificationReport?.allPassed ?? false;

  /// Overall deployment status.
  String get statusLabel {
    if (isBuilding) return 'Building...';
    if (isVerifying) return 'Verifying...';
    if (errorMessage != null) return 'Error';
    if (verificationReport != null) {
      return verificationReport!.allPassed ? 'Ready for Release' : 'Verification Failed';
    }
    if (allStagesPassed) return 'All Gates Passed';
    if (hasStageFailures) return 'Pipeline Failed';
    return 'Pending';
  }

  DeploymentState copyWith({
    EnvironmentConfig? buildConfig,
    CiCdPipeline? pipeline,
    List<StageResultRecord>? stageResults,
    HealthReport? healthReport,
    ReleaseVerificationReport? verificationReport,
    bool? isBuilding,
    bool? isVerifying,
    String? errorMessage,
  }) {
    return DeploymentState(
      buildConfig: buildConfig ?? this.buildConfig,
      pipeline: pipeline ?? this.pipeline,
      stageResults: stageResults ?? this.stageResults,
      healthReport: healthReport ?? this.healthReport,
      verificationReport: verificationReport ?? this.verificationReport,
      isBuilding: isBuilding ?? this.isBuilding,
      isVerifying: isVerifying ?? this.isVerifying,
      errorMessage: errorMessage,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DeploymentState &&
          runtimeType == other.runtimeType &&
          buildConfig == other.buildConfig &&
          isBuilding == other.isBuilding &&
          isVerifying == other.isVerifying;

  @override
  int get hashCode => Object.hash(buildConfig, isBuilding, isVerifying);
}
