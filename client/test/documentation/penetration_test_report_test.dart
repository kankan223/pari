import 'package:civic_commons/documentation/domain/penetration_test_report.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Task 15.4 — Penetration Test Report Domain', () {
    group('PentestSeverity', () {
      test('has 5 severity levels', () {
        expect(PentestSeverity.values.length, 5);
      });

      test('label returns capitalized name', () {
        expect(PentestSeverity.informational.label, 'Informational');
        expect(PentestSeverity.low.label, 'Low');
        expect(PentestSeverity.medium.label, 'Medium');
        expect(PentestSeverity.high.label, 'High');
        expect(PentestSeverity.critical.label, 'Critical');
      });

      test('weight returns ascending order', () {
        expect(PentestSeverity.informational.weight, 0);
        expect(PentestSeverity.low.weight, 1);
        expect(PentestSeverity.medium.weight, 2);
        expect(PentestSeverity.high.weight, 3);
        expect(PentestSeverity.critical.weight, 4);
      });
    });

    group('FindingStatus', () {
      test('has 6 statuses', () {
        expect(FindingStatus.values.length, 6);
      });

      test('label returns human-readable name', () {
        expect(FindingStatus.open.label, 'Open');
        expect(FindingStatus.inProgress.label, 'In Progress');
        expect(FindingStatus.fixPendingVerification.label, 'Fix Pending Verification');
        expect(FindingStatus.resolved.label, 'Resolved');
        expect(FindingStatus.acceptedRisk.label, 'Accepted Risk');
        expect(FindingStatus.falsePositive.label, 'False Positive');
      });
    });

    group('PentestFinding', () {
      test('constructs with required fields', () {
        const finding = PentestFinding(
          id: 'PTF-001',
          title: 'XSS in profile',
          description: 'Cross-site scripting in profile page.',
          severity: PentestSeverity.medium,
          affectedComponent: 'ProfileScreen',
          stepsToReproduce: '1. Navigate to profile...',
          remediation: 'Sanitize user input.',
          discoveredDate: '2026-08-21',
        );
        expect(finding.id, 'PTF-001');
        expect(finding.status, FindingStatus.open);
        expect(finding.isClosed, false);
        expect(finding.requiresAttention, false);
      });

      test('isClosed for resolved/accepted/falsePositive', () {
        const resolved = PentestFinding(
          id: 'F1', title: 'T', description: 'D', severity: PentestSeverity.high,
          status: FindingStatus.resolved, affectedComponent: 'C',
          stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01',
        );
        const accepted = PentestFinding(
          id: 'F2', title: 'T', description: 'D', severity: PentestSeverity.critical,
          status: FindingStatus.acceptedRisk, affectedComponent: 'C',
          stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01',
        );
        const open = PentestFinding(
          id: 'F3', title: 'T', description: 'D', severity: PentestSeverity.high,
          affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
          discoveredDate: '2026-01-01',
        );
        expect(resolved.isClosed, true);
        expect(accepted.isClosed, true);
        expect(open.isClosed, false);
      });

      test('requiresAttention for open high/critical', () {
        const highOpen = PentestFinding(
          id: 'F1', title: 'T', description: 'D', severity: PentestSeverity.high,
          affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
          discoveredDate: '2026-01-01',
        );
        const criticalResolved = PentestFinding(
          id: 'F2', title: 'T', description: 'D', severity: PentestSeverity.critical,
          status: FindingStatus.resolved, affectedComponent: 'C',
          stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01',
        );
        const lowOpen = PentestFinding(
          id: 'F3', title: 'T', description: 'D', severity: PentestSeverity.low,
          affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
          discoveredDate: '2026-01-01',
        );
        expect(highOpen.requiresAttention, true);
        expect(criticalResolved.requiresAttention, false);
        expect(lowOpen.requiresAttention, false);
      });

      test('equality by id', () {
        const a = PentestFinding(
          id: 'F1', title: 'A', description: 'D', severity: PentestSeverity.low,
          affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
          discoveredDate: '2026-01-01',
        );
        const b = PentestFinding(
          id: 'F1', title: 'B', description: 'E', severity: PentestSeverity.critical,
          affectedComponent: 'X', stepsToReproduce: 'Y', remediation: 'Z',
          discoveredDate: '2026-12-31',
        );
        const c = PentestFinding(
          id: 'F2', title: 'A', description: 'D', severity: PentestSeverity.low,
          affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
          discoveredDate: '2026-01-01',
        );
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PentestReport', () {
      test('constructs with findings', () {
        const report = PentestReport(
          id: 'PENTEST-2026-Q3',
          scope: 'Full application',
          methodology: 'OWASP Testing Guide',
          testDate: '2026-08-21',
          findings: [
            PentestFinding(
              id: 'F1', title: 'Low', description: 'D', severity: PentestSeverity.low,
              affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
              discoveredDate: '2026-08-21',
            ),
            PentestFinding(
              id: 'F2', title: 'Critical', description: 'D', severity: PentestSeverity.critical,
              affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R',
              discoveredDate: '2026-08-21',
            ),
          ],
        );
        expect(report.findingCount, 2);
        expect(report.criticalCount, 1);
        expect(report.highCount, 0);
      });

      test('findBySeverity filters correctly', () {
        const report = PentestReport(
          id: 'R1', scope: 'S', methodology: 'M', testDate: '2026-01-01',
          findings: [
            PentestFinding(id: 'F1', title: 'H1', description: 'D', severity: PentestSeverity.high, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
            PentestFinding(id: 'F2', title: 'H2', description: 'D', severity: PentestSeverity.high, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
            PentestFinding(id: 'F3', title: 'L', description: 'D', severity: PentestSeverity.low, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
          ],
        );
        expect(report.findBySeverity(PentestSeverity.high).length, 2);
        expect(report.findBySeverity(PentestSeverity.low).length, 1);
      });

      test('openFindings returns only unresolved high/critical', () {
        const report = PentestReport(
          id: 'R1', scope: 'S', methodology: 'M', testDate: '2026-01-01',
          findings: [
            PentestFinding(id: 'F1', title: 'Open High', description: 'D', severity: PentestSeverity.high, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
            PentestFinding(id: 'F2', title: 'Resolved', description: 'D', severity: PentestSeverity.critical, status: FindingStatus.resolved, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
            PentestFinding(id: 'F3', title: 'Low Open', description: 'D', severity: PentestSeverity.low, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
          ],
        );
        expect(report.openFindings.length, 1);
        expect(report.resolvedFindings.length, 1);
      });

      test('allCriticalResolved is true when no open high/critical', () {
        const resolved = PentestReport(
          id: 'R1', scope: 'S', methodology: 'M', testDate: '2026-01-01',
          findings: [
            PentestFinding(id: 'F1', title: 'Fixed', description: 'D', severity: PentestSeverity.critical, status: FindingStatus.resolved, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
          ],
        );
        const withOpen = PentestReport(
          id: 'R2', scope: 'S', methodology: 'M', testDate: '2026-01-01',
          findings: [
            PentestFinding(id: 'F1', title: 'Open', description: 'D', severity: PentestSeverity.high, affectedComponent: 'C', stepsToReproduce: 'S', remediation: 'R', discoveredDate: '2026-01-01'),
          ],
        );
        expect(resolved.allCriticalResolved, true);
        expect(withOpen.allCriticalResolved, false);
      });

      test('equality by id', () {
        const a = PentestReport(id: 'R1', scope: 'S', methodology: 'M', testDate: '2026-01-01');
        const b = PentestReport(id: 'R1', scope: 'X', methodology: 'Y', testDate: '2026-12-31');
        const c = PentestReport(id: 'R2', scope: 'S', methodology: 'M', testDate: '2026-01-01');
        expect(a, equals(b));
        expect(a, isNot(equals(c)));
      });
    });

    group('PII audit', () {
      test('no PII in severity labels', () {
        for (final sev in PentestSeverity.values) {
          expect(sev.label, isNot(contains('@')));
          expect(sev.label, isNot(contains(RegExp(r'\+[0-9]{10}'))));
        }
      });

      test('no PII in status labels', () {
        for (final status in FindingStatus.values) {
          expect(status.label, isNot(contains('@')));
        }
      });
    });
  });
}
