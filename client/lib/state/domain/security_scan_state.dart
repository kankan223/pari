import 'package:civic_commons/security/domain/penetration_test_scenario.dart';
import 'package:civic_commons/security/domain/security_scan_result.dart';
import 'package:civic_commons/security/domain/vulnerability_finding.dart';

/// State for the security scanning feature (Task 13.4).
///
/// Carries only scan metadata, findings, and status — zero PII.
class SecurityScanState {
  /// Current scan status.
  final SecurityScanStatus status;

  /// Result of the most recent scan (null if no scan has run).
  final SecurityScanResult? lastScanResult;

  /// All acknowledged findings.
  final List<VulnerabilityFinding> acknowledgedFindings;

  /// Penetration test results.
  final List<PenetrationTestResult> pentestResults;

  /// Error message if the scan failed (null on success).
  final String? errorMessage;

  /// Whether a scan is currently in progress.
  final bool isScanning;

  /// Whether penetration tests are running.
  final bool isRunningPentests;

  const SecurityScanState({
    this.status = SecurityScanStatus.idle,
    this.lastScanResult,
    this.acknowledgedFindings = const [],
    this.pentestResults = const [],
    this.errorMessage,
    this.isScanning = false,
    this.isRunningPentests = false,
  });

  /// Total number of findings.
  int get findingCount => lastScanResult?.findingCount ?? 0;

  /// Whether the last scan passed (zero critical/high).
  bool get scanPassed => lastScanResult?.passed ?? true;

  /// Risk score from the last scan.
  int get riskScore => lastScanResult?.riskScore ?? 0;

  /// Total penetration tests that resisted attacks.
  int get pentestsResisted =>
      pentestResults.where((r) => r.resisted).length;

  /// Total penetration tests that failed.
  int get pentestsFailed =>
      pentestResults.where((r) => !r.resisted).length;

  /// Whether all penetration tests passed.
  bool get allPentestsPassed =>
      pentestResults.isNotEmpty && pentestsFailed == 0;

  SecurityScanState copyWith({
    SecurityScanStatus? status,
    SecurityScanResult? lastScanResult,
    List<VulnerabilityFinding>? acknowledgedFindings,
    List<PenetrationTestResult>? pentestResults,
    String? errorMessage,
    bool? isScanning,
    bool? isRunningPentests,
  }) {
    return SecurityScanState(
      status: status ?? this.status,
      lastScanResult: lastScanResult ?? this.lastScanResult,
      acknowledgedFindings:
          acknowledgedFindings ?? this.acknowledgedFindings,
      pentestResults: pentestResults ?? this.pentestResults,
      errorMessage: errorMessage,
      isScanning: isScanning ?? this.isScanning,
      isRunningPentests: isRunningPentests ?? this.isRunningPentests,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityScanState &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          lastScanResult == other.lastScanResult &&
          isScanning == other.isScanning &&
          isRunningPentests == other.isRunningPentests;

  @override
  int get hashCode =>
      status.hashCode ^
      lastScanResult.hashCode ^
      isScanning.hashCode ^
      isRunningPentests.hashCode;
}

/// Status of the security scan.
enum SecurityScanStatus {
  /// No scan has been initiated.
  idle,

  /// Scan is in progress.
  scanning,

  /// Scan completed successfully.
  completed,

  /// Scan failed with an error.
  error,

  /// Penetration tests are running.
  pentesting,
}
