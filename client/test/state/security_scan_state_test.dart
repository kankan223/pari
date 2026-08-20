import 'package:civic_commons/security/domain/penetration_test_scenario.dart';
import 'package:civic_commons/security/domain/security_scan_result.dart';
import 'package:civic_commons/security/domain/vulnerability_finding.dart';
import 'package:civic_commons/security/domain/vulnerability_severity.dart';
import 'package:civic_commons/security/domain/vulnerability_type.dart';
import 'package:civic_commons/state/domain/security_scan_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecurityScanState', () {
    test('default state is idle with no results', () {
      const state = SecurityScanState();

      expect(state.status, SecurityScanStatus.idle);
      expect(state.lastScanResult, isNull);
      expect(state.isScanning, isFalse);
      expect(state.isRunningPentests, isFalse);
      expect(state.errorMessage, isNull);
      expect(state.findingCount, 0);
      expect(state.scanPassed, isTrue);
      expect(state.riskScore, 0);
      expect(state.pentestsResisted, 0);
      expect(state.pentestsFailed, 0);
      expect(state.allPentestsPassed, isFalse);
    });

    test('copyWith preserves unmodified fields', () {
      const original = SecurityScanState(
        status: SecurityScanStatus.scanning,
        isScanning: true,
      );

      final copied = original.copyWith(
        errorMessage: 'Test error',
      );

      expect(copied.status, SecurityScanStatus.scanning);
      expect(copied.isScanning, isTrue);
      expect(copied.errorMessage, 'Test error');
    });

    test('copyWith overrides specified fields', () {
      const original = SecurityScanState(
        status: SecurityScanStatus.idle,
        isScanning: false,
      );

      final copied = original.copyWith(
        status: SecurityScanStatus.scanning,
        isScanning: true,
      );

      expect(copied.status, SecurityScanStatus.scanning);
      expect(copied.isScanning, isTrue);
    });

    test('findingCount delegates to lastScanResult', () {
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
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      final state = SecurityScanState(lastScanResult: result);
      expect(state.findingCount, 1);
    });

    test('scanPassed delegates to lastScanResult', () {
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
            recommendation: 'Fix',
            detectedAtMs: 1500,
          ),
        ],
        filesScanned: 5,
        linesAnalyzed: 100,
      );

      final state = SecurityScanState(lastScanResult: result);
      expect(state.scanPassed, isFalse);
    });

    test('pentestsResisted counts correctly', () {
      final state = SecurityScanState(
        pentestResults: [
          PenetrationTestResult(
            type: PenetrationTestType.sqlInjection,
            resisted: true,
            description: 'Passed',
            durationMs: 100,
          ),
          PenetrationTestResult(
            type: PenetrationTestType.authBypass,
            resisted: false,
            description: 'Failed',
            durationMs: 100,
          ),
          PenetrationTestResult(
            type: PenetrationTestType.bufferOverflow,
            resisted: true,
            description: 'Passed',
            durationMs: 100,
          ),
        ],
      );

      expect(state.pentestsResisted, 2);
      expect(state.pentestsFailed, 1);
    });

    test('allPentestsPassed returns true when all resisted', () {
      final state = SecurityScanState(
        pentestResults: [
          PenetrationTestResult(
            type: PenetrationTestType.sqlInjection,
            resisted: true,
            description: 'Passed',
            durationMs: 100,
          ),
          PenetrationTestResult(
            type: PenetrationTestType.authBypass,
            resisted: true,
            description: 'Passed',
            durationMs: 100,
          ),
        ],
      );

      expect(state.allPentestsPassed, isTrue);
    });

    test('allPentestsPassed returns false when any failed', () {
      final state = SecurityScanState(
        pentestResults: [
          PenetrationTestResult(
            type: PenetrationTestType.sqlInjection,
            resisted: true,
            description: 'Passed',
            durationMs: 100,
          ),
          PenetrationTestResult(
            type: PenetrationTestType.authBypass,
            resisted: false,
            description: 'Failed',
            durationMs: 100,
          ),
        ],
      );

      expect(state.allPentestsPassed, isFalse);
    });

    test('allPentestsPassed returns false when no tests run', () {
      const state = SecurityScanState();
      expect(state.allPentestsPassed, isFalse);
    });

    test('equality by status, lastScanResult, isScanning, isRunningPentests',
        () {
      const a = SecurityScanState(
        status: SecurityScanStatus.idle,
        isScanning: false,
        isRunningPentests: false,
      );

      const b = SecurityScanState(
        status: SecurityScanStatus.idle,
        isScanning: false,
        isRunningPentests: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });
  });

  group('SecurityScanStatus', () {
    test('has 5 enum values', () {
      expect(SecurityScanStatus.values.length, 5);
    });
  });
}
