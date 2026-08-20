import 'package:civic_commons/security/domain/penetration_test_scenario.dart';
import 'package:civic_commons/security/domain/security_scan_result.dart';
import 'package:civic_commons/security/domain/security_scanner_port.dart';
import 'package:civic_commons/security/domain/vulnerability_finding.dart';
import 'package:civic_commons/security/domain/vulnerability_severity.dart';
import 'package:civic_commons/security/domain/vulnerability_type.dart';

/// Fake security scanner for testing (Task 13.4).
class FakeSecurityScanner implements SecurityScannerPort {
  /// Whether scan should fail.
  bool shouldFailScan = false;

  /// Whether penetration tests should fail.
  bool shouldFailPentests = false;

  /// Simulated scan delay.
  Duration scanDelay = Duration.zero;

  /// Number of times scanCodebase was called.
  int scanCallCount = 0;

  /// Number of times scanForSecrets was called.
  int secretScanCallCount = 0;

  /// Number of times runAllPenetrationTests was called.
  int pentestCallCount = 0;

  /// Fake findings to return.
  List<VulnerabilityFinding> fakeFindings = [
    VulnerabilityFinding(
      id: 'fake-finding-1',
      type: VulnerabilityType.hardcodedSecret,
      severity: VulnerabilitySeverity.critical,
      filePath: 'lib/test.dart',
      lineNumber: 10,
      description: 'Hardcoded password detected',
      recommendation: 'Use secure storage',
      detectedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
    VulnerabilityFinding(
      id: 'fake-finding-2',
      type: VulnerabilityType.weakCryptography,
      severity: VulnerabilitySeverity.low,
      filePath: 'lib/crypto.dart',
      lineNumber: 25,
      description: 'Deprecated algorithm',
      recommendation: 'Use SHA-256',
      detectedAtMs: DateTime.now().millisecondsSinceEpoch,
    ),
  ];

  @override
  Future<SecurityScanResult> scanCodebase() async {
    scanCallCount++;
    if (scanDelay > Duration.zero) {
      await Future.delayed(scanDelay);
    }
    if (shouldFailScan) {
      throw Exception('Scan failed');
    }

    return SecurityScanResult(
      scanId: 'fake-scan-$scanCallCount',
      startedAtMs: DateTime.now().millisecondsSinceEpoch - 1000,
      completedAtMs: DateTime.now().millisecondsSinceEpoch,
      findings: fakeFindings,
      filesScanned: 42,
      linesAnalyzed: 1234,
    );
  }

  @override
  Future<List<VulnerabilityFinding>> scanForSecrets() async {
    secretScanCallCount++;
    if (shouldFailScan) {
      throw Exception('Secret scan failed');
    }
    return fakeFindings
        .where((f) => f.type == VulnerabilityType.hardcodedSecret)
        .toList();
  }

  @override
  Future<PenetrationTestResult> runPenetrationTest(
    PenetrationTestType type,
  ) async {
    if (shouldFailPentests) {
      throw Exception('Penetration test failed');
    }

    return PenetrationTestResult(
      type: type,
      resisted: true,
      description: '${type.label} test passed',
      durationMs: 50,
    );
  }

  @override
  Future<List<PenetrationTestResult>> runAllPenetrationTests() async {
    pentestCallCount++;
    if (shouldFailPentests) {
      throw Exception('Penetration tests failed');
    }

    return PenetrationTestType.values
        .map((type) => PenetrationTestResult(
              type: type,
              resisted: true,
              description: '${type.label} test passed',
              durationMs: 50,
            ))
        .toList();
  }

  @override
  Future<int> getFileCount() async => 42;
}
