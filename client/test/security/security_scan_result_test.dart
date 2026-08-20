import 'package:civic_commons/security/domain/security_scan_result.dart';
import 'package:civic_commons/security/domain/vulnerability_finding.dart';
import 'package:civic_commons/security/domain/vulnerability_severity.dart';
import 'package:civic_commons/security/domain/vulnerability_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecurityScanResult', () {
    test('empty factory creates result with no findings', () {
      final result = SecurityScanResult.empty();

      expect(result.findings, isEmpty);
      expect(result.filesScanned, 0);
      expect(result.linesAnalyzed, 0);
      expect(result.passed, isTrue);
      expect(result.hasFindings, isFalse);
      expect(result.riskScore, 0);
    });

    test('countBySeverity counts correctly', () {
      final result = SecurityScanResult(
        scanId: 'scan-1',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: [
          VulnerabilityFinding(
            id: 'f1',
            type: VulnerabilityType.hardcodedSecret,
            severity: VulnerabilitySeverity.critical,
            filePath: 'lib/a.dart',
            lineNumber: 1,
            description: 'A',
            recommendation: 'Fix A',
            detectedAtMs: 1500,
          ),
          VulnerabilityFinding(
            id: 'f2',
            type: VulnerabilityType.hardcodedSecret,
            severity: VulnerabilitySeverity.critical,
            filePath: 'lib/b.dart',
            lineNumber: 2,
            description: 'B',
            recommendation: 'Fix B',
            detectedAtMs: 1500,
          ),
          VulnerabilityFinding(
            id: 'f3',
            type: VulnerabilityType.sqlInjection,
            severity: VulnerabilitySeverity.high,
            filePath: 'lib/c.dart',
            lineNumber: 3,
            description: 'C',
            recommendation: 'Fix C',
            detectedAtMs: 1500,
          ),
          VulnerabilityFinding(
            id: 'f4',
            type: VulnerabilityType.weakCryptography,
            severity: VulnerabilitySeverity.medium,
            filePath: 'lib/d.dart',
            lineNumber: 4,
            description: 'D',
            recommendation: 'Fix D',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 10,
        linesAnalyzed: 500,
      );

      expect(result.findingCount, 4);
      expect(result.criticalCount, 2);
      expect(result.highCount, 1);
      expect(result.mediumCount, 1);
      expect(result.lowCount, 0);
      expect(result.informationalCount, 0);
    });

    test('passed returns true when zero critical and high', () {
      final result = SecurityScanResult(
        scanId: 'scan-2',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: [
          VulnerabilityFinding(
            id: 'f1',
            type: VulnerabilityType.weakCryptography,
            severity: VulnerabilitySeverity.low,
            filePath: 'lib/a.dart',
            lineNumber: 1,
            description: 'Low issue',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      expect(result.passed, isTrue);
    });

    test('passed returns false when critical findings exist', () {
      final result = SecurityScanResult(
        scanId: 'scan-3',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: [
          VulnerabilityFinding(
            id: 'f1',
            type: VulnerabilityType.hardcodedSecret,
            severity: VulnerabilitySeverity.critical,
            filePath: 'lib/a.dart',
            lineNumber: 1,
            description: 'Critical issue',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      expect(result.passed, isFalse);
    });

    test('passed returns false when high findings exist', () {
      final result = SecurityScanResult(
        scanId: 'scan-4',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: [
          VulnerabilityFinding(
            id: 'f1',
            type: VulnerabilityType.sqlInjection,
            severity: VulnerabilitySeverity.high,
            filePath: 'lib/a.dart',
            lineNumber: 1,
            description: 'High issue',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      expect(result.passed, isFalse);
    });

    test('riskScore sums severity weights', () {
      final result = SecurityScanResult(
        scanId: 'scan-5',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: [
          VulnerabilityFinding(
            id: 'f1',
            type: VulnerabilityType.hardcodedSecret,
            severity: VulnerabilitySeverity.critical, // weight 10
            filePath: 'lib/a.dart',
            lineNumber: 1,
            description: 'A',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
          VulnerabilityFinding(
            id: 'f2',
            type: VulnerabilityType.sqlInjection,
            severity: VulnerabilitySeverity.high, // weight 7
            filePath: 'lib/b.dart',
            lineNumber: 2,
            description: 'B',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
          VulnerabilityFinding(
            id: 'f3',
            type: VulnerabilityType.weakCryptography,
            severity: VulnerabilitySeverity.low, // weight 2
            filePath: 'lib/c.dart',
            lineNumber: 3,
            description: 'C',
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      expect(result.riskScore, 19); // 10 + 7 + 2
    });

    test('durationMs calculates correctly', () {
      final result = SecurityScanResult(
        scanId: 'scan-6',
        startedAtMs: 1000,
        completedAtMs: 3500,
        findings: const [],
        filesScanned: 10,
        linesAnalyzed: 500,
      );

      expect(result.durationMs, 2500);
    });

    test('equality by scanId', () {
      final a = SecurityScanResult(
        scanId: 'same-id',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: const [],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      final b = SecurityScanResult(
        scanId: 'same-id',
        startedAtMs: 5000,
        completedAtMs: 6000,
        findings: const [],
        filesScanned: 20,
        linesAnalyzed: 1000,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different scanId', () {
      final a = SecurityScanResult(
        scanId: 'id-1',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: const [],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      final b = SecurityScanResult(
        scanId: 'id-2',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: const [],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      expect(a, isNot(equals(b)));
    });

    test('no PII in scan result', () {
      final result = SecurityScanResult(
        scanId: 'scan-pii',
        startedAtMs: 1000,
        completedAtMs: 2000,
        findings: const [],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      final str = result.toString();
      expect(str, isNot(contains('phone')));
      expect(str, isNot(contains('email')));
      expect(str, isNot(contains('+91')));
      expect(str, isNot(contains('password')));
    });
  });
}
