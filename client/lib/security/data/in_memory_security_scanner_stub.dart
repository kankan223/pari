import '../domain/penetration_test_scenario.dart';
import '../domain/scanner_config.dart';
import '../domain/secret_scan_config.dart';
import '../domain/security_scan_result.dart';
import '../domain/security_scanner_port.dart';
import '../domain/vulnerability_finding.dart';

/// Web stub: filesystem scanning is unavailable on web (dart:io unsupported).
/// Returns empty scan results so the security scan screen still renders
/// without crashing the app.
class InMemorySecurityScanner implements SecurityScannerPort {
  final String rootDir;
  final List<SecretScanPattern> secretPatterns;
  final List<ScannerPattern> vulnPatterns;

  InMemorySecurityScanner({
    this.rootDir = 'lib',
    List<SecretScanPattern>? secretPatterns,
    List<ScannerPattern>? vulnPatterns,
  })  : secretPatterns = secretPatterns ?? SecretScanPattern.defaultPatterns,
        vulnPatterns = vulnPatterns ?? ScannerPattern.defaultPatterns;

  @override
  Future<SecurityScanResult> scanCodebase() async => SecurityScanResult(
        scanId: 'web-stub',
        startedAtMs: DateTime.now().millisecondsSinceEpoch,
        completedAtMs: DateTime.now().millisecondsSinceEpoch,
        filesScanned: 0,
        linesAnalyzed: 0,
        findings: const [],
      );

  @override
  Future<List<VulnerabilityFinding>> scanForSecrets() async => const [];

  @override
  Future<PenetrationTestResult> runPenetrationTest(
    PenetrationTestType type,
  ) async =>
      PenetrationTestResult(
        type: type,
        resisted: true,
        description: 'Web stub — no filesystem available',
        durationMs: 0,
      );

  @override
  Future<List<PenetrationTestResult>> runAllPenetrationTests() async => [];

  @override
  Future<int> getFileCount() async => 0;
}
