import 'vulnerability_finding.dart';
import 'vulnerability_severity.dart';

/// Aggregated result of a security scan (Task 13.4).
///
/// Contains all findings from a single scan run plus summary statistics.
/// The result is immutable and carries zero PII.
class SecurityScanResult {
  /// Unique scan run identifier (UUID v4).
  final String scanId;

  /// Timestamp when the scan started (milliseconds since epoch).
  final int startedAtMs;

  /// Timestamp when the scan completed (milliseconds since epoch).
  final int completedAtMs;

  /// All vulnerability findings detected during this scan.
  final List<VulnerabilityFinding> findings;

  /// Total number of files scanned.
  final int filesScanned;

  /// Total number of lines of code analyzed.
  final int linesAnalyzed;

  /// Duration of the scan in milliseconds.
  int get durationMs => completedAtMs - startedAtMs;

  /// Whether the scan completed without errors.
  final bool scanCompleted;

  /// Error message if the scan failed (null on success).
  final String? errorMessage;

  const SecurityScanResult({
    required this.scanId,
    required this.startedAtMs,
    required this.completedAtMs,
    required this.findings,
    required this.filesScanned,
    required this.linesAnalyzed,
    this.scanCompleted = true,
    this.errorMessage,
  });

  /// Empty scan result with no findings.
  factory SecurityScanResult.empty() => SecurityScanResult(
        scanId: '00000000-0000-0000-0000-000000000000',
        startedAtMs: 0,
        completedAtMs: 0,
        findings: const [],
        filesScanned: 0,
        linesAnalyzed: 0,
      );

  /// Total number of findings.
  int get findingCount => findings.length;

  /// Number of findings by severity.
  int countBySeverity(VulnerabilitySeverity severity) =>
      findings.where((f) => f.severity == severity).length;

  /// Number of critical findings.
  int get criticalCount => countBySeverity(VulnerabilitySeverity.critical);

  /// Number of high-severity findings.
  int get highCount => countBySeverity(VulnerabilitySeverity.high);

  /// Number of medium-severity findings.
  int get mediumCount => countBySeverity(VulnerabilitySeverity.medium);

  /// Number of low-severity findings.
  int get lowCount => countBySeverity(VulnerabilitySeverity.low);

  /// Number of informational findings.
  int get informationalCount =>
      countBySeverity(VulnerabilitySeverity.informational);

  /// Whether the scan passed (zero critical and high findings).
  bool get passed => criticalCount == 0 && highCount == 0;

  /// Whether there are any findings at all.
  bool get hasFindings => findings.isNotEmpty;

  /// Severity-weighted risk score (higher = worse).
  int get riskScore =>
      findings.fold(0, (sum, f) => sum + f.severity.weight);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SecurityScanResult &&
          runtimeType == other.runtimeType &&
          scanId == other.scanId;

  @override
  int get hashCode => scanId.hashCode;
}
