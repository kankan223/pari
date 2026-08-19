import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditAction', () {
    test('has exactly six audit action types', () {
      expect(AuditAction.values.length, 6);
    });

    test('wire round-trip for every type', () {
      for (final action in AuditAction.values) {
        final decoded = AuditAction.fromWireName(action.name);
        expect(decoded, action);
      }
    });

    test('labels and shortLabels are non-empty', () {
      for (final action in AuditAction.values) {
        expect(action.label.isNotEmpty, true);
        expect(action.shortLabel.isNotEmpty, true);
      }
    });

    test('unknown wire name throws FormatException', () {
      expect(
        () => AuditAction.fromWireName('unknown_action'),
        throwsFormatException,
      );
    });

    test('empty wire name throws FormatException', () {
      expect(
        () => AuditAction.fromWireName(''),
        throwsFormatException,
      );
    });

    test('shortLabel is shorter than or equal to label', () {
      for (final action in AuditAction.values) {
        expect(action.shortLabel.length <= action.label.length, true);
      }
    });
  });
}
