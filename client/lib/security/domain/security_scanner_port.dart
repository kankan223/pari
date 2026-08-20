import 'penetration_test_scenario.dart';
import 'security_scan_result.dart';
import 'vulnerability_finding.dart';

/// Port for the automated security scanner (Task 13.4).
///
/// Responsibilities:
/// 1. Scan source code for known vulnerability patterns.
/// 2. Execute secret scanning against configurable patterns.
/// 3. Run penetration test scenarios against the codebase.
/// 4. Produce a [SecurityScanResult] with all findings.
///
/// Security contract:
/// - The scanner performs ONLY static analysis — no runtime exploitation.
/// - No user data, PII, or identity information is ever scanned or logged.
/// - All findings reference file paths and line numbers, never user content.
abstract class SecurityScannerPort {
  /// Scan source code for vulnerability patterns.
  Future<SecurityScanResult> scanCodebase();

  /// Scan for hardcoded secrets using configured patterns.
  Future<List<VulnerabilityFinding>> scanForSecrets();

  /// Run a specific penetration test scenario.
  Future<PenetrationTestResult> runPenetrationTest(PenetrationTestType type);

  /// Run all configured penetration test scenarios.
  Future<List<PenetrationTestResult>> runAllPenetrationTests();

  /// Get the total number of files that can be scanned.
  Future<int> getFileCount();
}
