import 'package:civic_commons/documentation/domain/runbook.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('IncidentSeverity', () {
    test('has 5 levels', () {
      expect(IncidentSeverity.values.length, 5);
    });

    test('labels are human-readable', () {
      expect(IncidentSeverity.informational.label, 'Informational');
      expect(IncidentSeverity.low.label, 'Low');
      expect(IncidentSeverity.medium.label, 'Medium');
      expect(IncidentSeverity.high.label, 'High');
      expect(IncidentSeverity.critical.label, 'Critical');
    });

    test('weights are ordered', () {
      expect(IncidentSeverity.informational.weight, 0);
      expect(IncidentSeverity.low.weight, 1);
      expect(IncidentSeverity.medium.weight, 2);
      expect(IncidentSeverity.high.weight, 3);
      expect(IncidentSeverity.critical.weight, 4);
    });

    test('weights are monotonically increasing', () {
      final weights = IncidentSeverity.values.map((s) => s.weight).toList();
      for (var i = 1; i < weights.length; i++) {
        expect(weights[i], greaterThan(weights[i - 1]));
      }
    });
  });

  group('RunbookCategory', () {
    test('has 6 categories', () {
      expect(RunbookCategory.values.length, 6);
    });

    test('labels are human-readable', () {
      expect(RunbookCategory.rollback.label, 'Rollback');
      expect(RunbookCategory.scaling.label, 'Scaling');
      expect(RunbookCategory.incidentResponse.label, 'Incident Response');
      expect(RunbookCategory.databaseMaintenance.label, 'Database Maintenance');
      expect(RunbookCategory.certificateRotation.label, 'Certificate Rotation');
      expect(
          RunbookCategory.performanceDegradation.label, 'Performance Degradation');
    });
  });

  group('RunbookStep', () {
    test('constructs with required fields', () {
      final step = RunbookStep(
        number: 1,
        title: 'Stop traffic',
        action: 'Scale gateway to 0 replicas',
      );
      expect(step.number, 1);
      expect(step.title, 'Stop traffic');
      expect(step.action, 'Scale gateway to 0 replicas');
      expect(step.estimatedDuration, const Duration(minutes: 2));
      expect(step.requiresManualIntervention, false);
      expect(step.safetyWarning, isNull);
    });

    test('estimatedMinutes converts duration', () {
      final step = RunbookStep(
        number: 1,
        title: 'Rollback',
        action: 'Revert to previous version',
        estimatedDuration: const Duration(minutes: 10),
      );
      expect(step.estimatedMinutes, 10);
    });

    test('equality by number and title', () {
      final a = RunbookStep(number: 1, title: 'Stop', action: 'Stop');
      final b = RunbookStep(number: 1, title: 'Stop', action: 'Stop');
      final c = RunbookStep(number: 2, title: 'Stop', action: 'Stop');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('Runbook', () {
    test('constructs with steps', () {
      final steps = [
        RunbookStep(number: 1, title: 'Stop', action: 'Stop traffic'),
        RunbookStep(number: 2, title: 'Rollback', action: 'Revert'),
      ];
      final runbook = Runbook(
        id: 'rb-rollback',
        title: 'Emergency Rollback',
        category: RunbookCategory.rollback,
        severity: IncidentSeverity.critical,
        steps: steps,
        requiresUserNotification: true,
        escalationContacts: ['on-call-engineer', 'team-lead'],
      );
      expect(runbook.id, 'rb-rollback');
      expect(runbook.steps.length, 2);
      expect(runbook.requiresUserNotification, true);
      expect(runbook.escalationContacts.length, 2);
    });

    test('manualStepCount counts manual intervention steps', () {
      final steps = [
        RunbookStep(
            number: 1,
            title: 'Stop',
            action: 'Stop',
            requiresManualIntervention: true),
        RunbookStep(
            number: 2, title: 'Rollback', action: 'Revert'),
      ];
      final runbook = Runbook(
        id: 'rb1',
        title: 'R1',
        category: RunbookCategory.rollback,
        severity: IncidentSeverity.high,
        steps: steps,
      );
      expect(runbook.manualStepCount, 1);
    });

    test('hasSafetyWarnings detects safety warnings', () {
      final stepsWithWarning = [
        RunbookStep(
            number: 1,
            title: 'Delete',
            action: 'Delete data',
            safetyWarning: 'This is irreversible'),
      ];
      final stepsWithout = [
        RunbookStep(number: 1, title: 'Deploy', action: 'Deploy'),
      ];
      expect(
          Runbook(
            id: 'r1',
            title: 'R1',
            category: RunbookCategory.rollback,
            severity: IncidentSeverity.high,
            steps: stepsWithWarning,
          ).hasSafetyWarnings,
          true);
      expect(
          Runbook(
            id: 'r2',
            title: 'R2',
            category: RunbookCategory.rollback,
            severity: IncidentSeverity.high,
            steps: stepsWithout,
          ).hasSafetyWarnings,
          false);
    });

    test('stepsWithFallbacks filters steps with failure actions', () {
      final steps = [
        RunbookStep(
            number: 1,
            title: 'Deploy',
            action: 'Deploy',
            failureAction: 'Revert to previous version'),
        RunbookStep(number: 2, title: 'Notify', action: 'Notify'),
      ];
      final runbook = Runbook(
        id: 'rb1',
        title: 'R1',
        category: RunbookCategory.rollback,
        severity: IncidentSeverity.high,
        steps: steps,
      );
      expect(runbook.stepsWithFallbacks.length, 1);
    });

    test('equality by id', () {
      final a = Runbook(
          id: 'rb1',
          title: 'R1',
          category: RunbookCategory.rollback,
          severity: IncidentSeverity.high,
          steps: []);
      final b = Runbook(
          id: 'rb1',
          title: 'R2',
          category: RunbookCategory.scaling,
          severity: IncidentSeverity.low,
          steps: []);
      final c = Runbook(
          id: 'rb2',
          title: 'R1',
          category: RunbookCategory.rollback,
          severity: IncidentSeverity.high,
          steps: []);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('RunbookIndex', () {
    test('empty index has 0 count', () {
      final index = RunbookIndex.empty();
      expect(index.count, 0);
      expect(index.all, isEmpty);
    });

    test('withRunbook adds runbook', () {
      final runbook = Runbook(
        id: 'rb1',
        title: 'Rollback',
        category: RunbookCategory.rollback,
        severity: IncidentSeverity.critical,
        steps: [],
      );
      final index = RunbookIndex.empty().withRunbook(runbook);
      expect(index.count, 1);
      expect(index.getById('rb1'), equals(runbook));
    });

    test('withoutRunbook removes runbook', () {
      final runbook = Runbook(
        id: 'rb1',
        title: 'Rollback',
        category: RunbookCategory.rollback,
        severity: IncidentSeverity.critical,
        steps: [],
      );
      final index = RunbookIndex.empty()
          .withRunbook(runbook)
          .withoutRunbook('rb1');
      expect(index.count, 0);
      expect(index.getById('rb1'), isNull);
    });

    test('getByCategory filters correctly', () {
      final rollback = Runbook(
          id: 'rb1',
          title: 'Rollback',
          category: RunbookCategory.rollback,
          severity: IncidentSeverity.high,
          steps: []);
      final scaling = Runbook(
          id: 'rb2',
          title: 'Scale',
          category: RunbookCategory.scaling,
          severity: IncidentSeverity.medium,
          steps: []);
      final index = RunbookIndex.empty()
          .withRunbook(rollback)
          .withRunbook(scaling);
      expect(index.getByCategory(RunbookCategory.rollback).length, 1);
      expect(index.getByCategory(RunbookCategory.scaling).length, 1);
    });

    test('criticalRunbooks returns only critical', () {
      final critical = Runbook(
          id: 'rb1',
          title: 'Critical',
          category: RunbookCategory.rollback,
          severity: IncidentSeverity.critical,
          steps: []);
      final low = Runbook(
          id: 'rb2',
          title: 'Low',
          category: RunbookCategory.scaling,
          severity: IncidentSeverity.low,
          steps: []);
      final index = RunbookIndex.empty()
          .withRunbook(critical)
          .withRunbook(low);
      expect(index.criticalRunbooks.length, 1);
      expect(index.criticalRunbooks.first.id, 'rb1');
    });

    test('equality by contents', () {
      final r = Runbook(
          id: 'rb1',
          title: 'R1',
          category: RunbookCategory.rollback,
          severity: IncidentSeverity.high,
          steps: []);
      final a = RunbookIndex.empty().withRunbook(r);
      final b = RunbookIndex.empty().withRunbook(r);
      expect(a, equals(b));
    });
  });

  group('PII audit', () {
    test('runbook labels have zero PII patterns', () {
      for (final cat in RunbookCategory.values) {
        expect(cat.label, isNot(contains('+')));
        expect(cat.label, isNot(contains('@')));
      }
      for (final sev in IncidentSeverity.values) {
        expect(sev.label, isNot(contains('+')));
        expect(sev.label, isNot(contains('@')));
      }
    });
  });
}
