import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationType', () {
    test('has exactly three types', () {
      expect(NotificationType.values.length, 3);
    });

    test('wire round-trip for every type', () {
      for (final type in NotificationType.values) {
        final decoded = NotificationType.fromWireName(type.wireName);
        expect(decoded, type);
      }
    });

    test('karmaEvent has correct wire name and label', () {
      expect(NotificationType.karmaEvent.wireName, 'karma_event');
      expect(NotificationType.karmaEvent.label, 'Karma');
    });

    test('caseAssignment has correct wire name and label', () {
      expect(NotificationType.caseAssignment.wireName, 'case_assignment');
      expect(NotificationType.caseAssignment.label, 'Case');
    });

    test('ledgerReviewRequest has correct wire name and label', () {
      expect(NotificationType.ledgerReviewRequest.wireName,
          'ledger_review_request');
      expect(NotificationType.ledgerReviewRequest.label, 'Ledger');
    });

    test('unknown wire name throws FormatException', () {
      expect(
        () => NotificationType.fromWireName('unknown_type'),
        throwsFormatException,
      );
    });

    test('empty wire name throws FormatException', () {
      expect(
        () => NotificationType.fromWireName(''),
        throwsFormatException,
      );
    });
  });
}
