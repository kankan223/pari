import 'package:civic_commons/documentation/domain/troubleshooting_guide.dart';
import 'package:civic_commons/documentation/domain/runbook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IssueCategory', () {
    test('has 6 categories', () {
      expect(IssueCategory.values.length, 6);
    });

    test('labels are human-readable', () {
      expect(IssueCategory.database.label, 'Database');
      expect(IssueCategory.network.label, 'Network');
      expect(IssueCategory.performance.label, 'Performance');
      expect(IssueCategory.authentication.label, 'Authentication');
      expect(IssueCategory.storage.label, 'Storage');
      expect(IssueCategory.runtime.label, 'Runtime');
    });
  });

  group('DiagnosticStep', () {
    test('constructs with required fields', () {
      final step = DiagnosticStep(
        number: 1,
        description: 'Check database connectivity',
        command: 'psql -c "SELECT 1"',
        expectedOutput: '1',
        unhealthyIndication: 'Connection refused',
      );
      expect(step.number, 1);
      expect(step.description, 'Check database connectivity');
    });

    test('equality by number and description', () {
      final a = DiagnosticStep(
          number: 1,
          description: 'Check DB',
          command: 'cmd',
          expectedOutput: 'ok',
          unhealthyIndication: 'fail');
      final b = DiagnosticStep(
          number: 1,
          description: 'Check DB',
          command: 'cmd',
          expectedOutput: 'ok',
          unhealthyIndication: 'fail');
      final c = DiagnosticStep(
          number: 2,
          description: 'Check DB',
          command: 'cmd',
          expectedOutput: 'ok',
          unhealthyIndication: 'fail');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('ResolutionStep', () {
    test('constructs with required fields', () {
      final step = ResolutionStep(
        number: 1,
        action: 'Restart database',
        details: 'Run systemctl restart postgresql',
      );
      expect(step.number, 1);
      expect(step.action, 'Restart database');
      expect(step.reversible, true);
      expect(step.estimatedDuration, const Duration(minutes: 5));
    });

    test('estimatedMinutes converts duration', () {
      final step = ResolutionStep(
        number: 1,
        action: 'Migrate',
        details: 'Run migrations',
        estimatedDuration: const Duration(minutes: 20),
      );
      expect(step.estimatedMinutes, 20);
    });

    test('equality by number and action', () {
      final a = ResolutionStep(number: 1, action: 'Restart', details: 'R');
      final b = ResolutionStep(number: 1, action: 'Restart', details: 'R');
      final c = ResolutionStep(number: 2, action: 'Restart', details: 'R');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('TroubleshootingEntry', () {
    test('constructs with diagnostics and resolutions', () {
      final entry = TroubleshootingEntry(
        id: 'TSHOOT-001',
        title: 'Database connection timeout',
        category: IssueCategory.database,
        severity: IncidentSeverity.high,
        symptoms: 'Cannot connect to database',
        rootCauses: ['Connection pool exhausted', 'Network issue'],
        diagnostics: [
          DiagnosticStep(
              number: 1,
              description: 'Check connectivity',
              command: 'ping db',
              expectedOutput: 'PONG',
              unhealthyIndication: 'Timeout'),
        ],
        resolutions: [
          ResolutionStep(
              number: 1, action: 'Restart pool', details: 'Restart'),
        ],
      );
      expect(entry.id, 'TSHOOT-001');
      expect(entry.rootCauses.length, 2);
      expect(entry.diagnosticCount, 1);
      expect(entry.resolutionCount, 1);
      expect(entry.totalStepCount, 2);
    });

    test('estimatedMinutes converts duration', () {
      final entry = TroubleshootingEntry(
        id: 'TSHOOT-001',
        title: 'Issue',
        category: IssueCategory.network,
        severity: IncidentSeverity.medium,
        symptoms: 'Slow network',
        rootCauses: ['Congestion'],
        diagnostics: [],
        resolutions: [],
        estimatedTimeToResolve: const Duration(minutes: 30),
      );
      expect(entry.estimatedMinutes, 30);
    });

    test('equality by id', () {
      final a = TroubleshootingEntry(
          id: 'T1',
          title: 'Issue',
          category: IssueCategory.database,        severity: IncidentSeverity.high,
        symptoms: 'sym',
        rootCauses: [],
        diagnostics: [],
        resolutions: []);
      final b = TroubleshootingEntry(
          id: 'T1',
          title: 'Other',
          category: IssueCategory.network,
          severity: IncidentSeverity.low,
          symptoms: 'sym2',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final c = TroubleshootingEntry(
          id: 'T2',
          title: 'Issue',
          category: IssueCategory.database,
          severity: IncidentSeverity.high,
          symptoms: 'sym',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('TroubleshootingGuide', () {
    test('constructs with entries', () {
      final entries = [
        TroubleshootingEntry(
            id: 'T1',
            title: 'DB issue',
            category: IssueCategory.database,
        severity: IncidentSeverity.high,
        symptoms: 'Cannot connect',
        rootCauses: ['Pool exhausted'],
            diagnostics: [],
            resolutions: []),
        TroubleshootingEntry(
            id: 'T2',
            title: 'Network issue',
            category: IssueCategory.network,
        severity: IncidentSeverity.medium,
        symptoms: 'Slow',
        rootCauses: ['Congestion'],
            diagnostics: [],
            resolutions: []),
      ];
      final guide = TroubleshootingGuide(
        systemName: 'Civic Commons',
        entries: entries,
        emergencyContacts: ['on-call-engineer'],
      );
      expect(guide.systemName, 'Civic Commons');
      expect(guide.issueCount, 2);
      expect(guide.emergencyContacts.length, 1);
    });

    test('getById returns matching entry', () {
      final entry = TroubleshootingEntry(
          id: 'T1',
          title: 'Issue',
          category: IssueCategory.database,
          severity: IncidentSeverity.high,
          symptoms: 'sym',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final guide = TroubleshootingGuide(
          systemName: 'S', entries: [entry]);
      expect(guide.getById('T1'), equals(entry));
      expect(guide.getById('T99'), isNull);
    });

    test('getByCategory filters correctly', () {
      final db = TroubleshootingEntry(
          id: 'T1',
          title: 'DB',
          category: IssueCategory.database,
          severity: IncidentSeverity.high,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final net = TroubleshootingEntry(
          id: 'T2',
          title: 'Net',
          category: IssueCategory.network,
          severity: IncidentSeverity.low,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final guide =
          TroubleshootingGuide(systemName: 'S', entries: [db, net]);
      expect(guide.getByCategory(IssueCategory.database).length, 1);
      expect(guide.getByCategory(IssueCategory.network).length, 1);
      expect(guide.getByCategory(IssueCategory.performance).length, 0);
    });

    test('getBySeverity filters correctly', () {
      final high = TroubleshootingEntry(
          id: 'T1',
          title: 'High',
          category: IssueCategory.database,
          severity: IncidentSeverity.high,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final low = TroubleshootingEntry(
          id: 'T2',
          title: 'Low',
          category: IssueCategory.database,
          severity: IncidentSeverity.low,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []);
      final guide =
          TroubleshootingGuide(systemName: 'S', entries: [high, low]);
      expect(guide.getBySeverity(IncidentSeverity.high).length, 1);
      expect(guide.getBySeverity(IncidentSeverity.low).length, 1);
      expect(guide.getBySeverity(IncidentSeverity.critical).length, 0);
    });

    test('affectedCategories returns unique categories', () {
      final entries = [
        TroubleshootingEntry(
            id: 'T1',
            title: 'A',
            category: IssueCategory.database,          severity: IncidentSeverity.high,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []),
        TroubleshootingEntry(
          id: 'T2',
          title: 'B',
          category: IssueCategory.database,
          severity: IncidentSeverity.low,
            symptoms: 's',
            rootCauses: [],
            diagnostics: [],
            resolutions: []),
        TroubleshootingEntry(
            id: 'T3',
            title: 'C',
            category: IssueCategory.network,
          severity: IncidentSeverity.medium,
          symptoms: 's',
          rootCauses: [],
          diagnostics: [],
          resolutions: []),
      ];
      final guide =
          TroubleshootingGuide(systemName: 'S', entries: entries);
      expect(guide.affectedCategories.length, 2);
      expect(guide.affectedCategories, contains(IssueCategory.database));
      expect(guide.affectedCategories, contains(IssueCategory.network));
    });

    test('equality by systemName', () {
      final a = TroubleshootingGuide(systemName: 'S1', entries: []);
      final b = TroubleshootingGuide(systemName: 'S1', entries: []);
      final c = TroubleshootingGuide(systemName: 'S2', entries: []);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('PII audit', () {
    test('issue category labels have zero PII patterns', () {
      for (final cat in IssueCategory.values) {
        expect(cat.label, isNot(contains('+')));
        expect(cat.label, isNot(contains('@')));
      }
    });
  });
}
