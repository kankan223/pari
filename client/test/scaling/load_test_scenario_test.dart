import 'package:civic_commons/scaling/domain/load_test_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LoadTestScenario - Task 12.4', () {
    test('default scenario has correct properties', () {
      const scenario = LoadTestScenario(
        id: 'test',
        name: 'Test Scenario',
        concurrentUsers: 100,
      );
      expect(scenario.id, 'test');
      expect(scenario.name, 'Test Scenario');
      expect(scenario.concurrentUsers, 100);
      expect(scenario.requestsPerUser, 10);
      expect(scenario.thinkTimeMs, 100);
      expect(scenario.pattern, LoadPattern.constant);
    });

    test('totalRequests computes correctly', () {
      const scenario = LoadTestScenario(
        id: 'test',
        name: 'Test',
        concurrentUsers: 50,
        requestsPerUser: 20,
      );
      expect(scenario.totalRequests, 1000);
    });

    test('rampUp factory creates correct scenario', () {
      const scenario = LoadTestScenario.rampUp(
        id: 'ramp',
        name: 'Ramp Test',
        concurrentUsers: 1000,
      );
      expect(scenario.pattern, LoadPattern.rampUp);
      expect(scenario.concurrentUsers, 1000);
    });

    test('spike factory creates correct scenario', () {
      const scenario = LoadTestScenario.spike(
        id: 'spike',
        name: 'Spike Test',
        concurrentUsers: 5000,
      );
      expect(scenario.pattern, LoadPattern.spike);
      expect(scenario.concurrentUsers, 5000);
      expect(scenario.thinkTimeMs, 0);
    });

    test('equality by id and concurrentUsers', () {
      const a = LoadTestScenario(id: 't', name: 'T', concurrentUsers: 100);
      const b = LoadTestScenario(id: 't', name: 'T', concurrentUsers: 100);
      const c = LoadTestScenario(id: 't', name: 'T', concurrentUsers: 200);
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('defaultLoadTestScenarios covers key scenarios', () {
      expect(defaultLoadTestScenarios, hasLength(5));
      final ids = defaultLoadTestScenarios.map((s) => s.id).toSet();
      expect(ids, contains('feed_baseline'));
      expect(ids, contains('feed_peak'));
      expect(ids, contains('ramp_to_10k'));
      expect(ids, contains('viral_spike'));
    });

    test('estimatedDurationMs is positive', () {
      for (final scenario in defaultLoadTestScenarios) {
        expect(scenario.estimatedDurationMs, greaterThan(0));
      }
    });
  });
}
