import 'package:civic_commons/security/domain/penetration_test_scenario.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PenetrationTestType', () {
    test('has 10 enum values', () {
      expect(PenetrationTestType.values.length, 10);
    });

    test('all labels are non-empty', () {
      for (final type in PenetrationTestType.values) {
        expect(type.label.isNotEmpty, isTrue,
            reason: '${type.name} has empty label');
      }
    });

    test('labels are unique', () {
      final labels =
          PenetrationTestType.values.map((t) => t.label).toSet();
      expect(labels.length, PenetrationTestType.values.length);
    });
  });

  group('PenetrationTestResult', () {
    test('constructs with all required fields', () {
      final result = PenetrationTestResult(
        type: PenetrationTestType.sqlInjection,
        resisted: true,
        description: 'SQL injection test passed',
        durationMs: 150,
      );

      expect(result.type, PenetrationTestType.sqlInjection);
      expect(result.resisted, isTrue);
      expect(result.description, 'SQL injection test passed');
      expect(result.durationMs, 150);
    });

    test('equality by type and resisted', () {
      final a = PenetrationTestResult(
        type: PenetrationTestType.authBypass,
        resisted: true,
        description: 'Test A',
        durationMs: 100,
      );

      final b = PenetrationTestResult(
        type: PenetrationTestType.authBypass,
        resisted: true,
        description: 'Test B',
        durationMs: 200,
      );

      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
    });

    test('inequality with different type', () {
      final a = PenetrationTestResult(
        type: PenetrationTestType.sqlInjection,
        resisted: true,
        description: 'Test',
        durationMs: 100,
      );

      final b = PenetrationTestResult(
        type: PenetrationTestType.authBypass,
        resisted: true,
        description: 'Test',
        durationMs: 100,
      );

      expect(a, isNot(equals(b)));
    });

    test('inequality with different resisted', () {
      final a = PenetrationTestResult(
        type: PenetrationTestType.sqlInjection,
        resisted: true,
        description: 'Test',
        durationMs: 100,
      );

      final b = PenetrationTestResult(
        type: PenetrationTestType.sqlInjection,
        resisted: false,
        description: 'Test',
        durationMs: 100,
      );

      expect(a, isNot(equals(b)));
    });

    test('no PII in result', () {
      final result = PenetrationTestResult(
        type: PenetrationTestType.dataLeakage,
        resisted: true,
        description: 'Data leakage test',
        durationMs: 50,
      );

      final str = result.toString();
      expect(str, isNot(contains('phone')));
      expect(str, isNot(contains('email')));
      expect(str, isNot(contains('+91')));
    });
  });
}
