import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_preferences.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:civic_commons/state/domain/notification_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationState', () {
    test('default state is idle with empty list', () {
      const state = NotificationState();
      expect(state.phase, NotificationPhase.idle);
      expect(state.notifications, isEmpty);
      expect(state.unreadCount, 0);
      expect(state.isTypeEnabled(NotificationType.karmaEvent), true);
    });

    test('forType filters by type', () {
      final state = NotificationState(
        phase: NotificationPhase.ready,
        notifications: [
          NotificationRecord(
            id: '1',
            type: NotificationType.karmaEvent,
            title: 'Karma',
            body: 'Body',
            createdAt: DateTime.utc(2026, 8, 18),
          ),
          NotificationRecord(
            id: '2',
            type: NotificationType.caseAssignment,
            title: 'Case',
            body: 'Body',
            createdAt: DateTime.utc(2026, 8, 18),
          ),
          NotificationRecord(
            id: '3',
            type: NotificationType.karmaEvent,
            title: 'Karma 2',
            body: 'Body',
            createdAt: DateTime.utc(2026, 8, 18),
          ),
        ],
      );

      final karma = state.forType(NotificationType.karmaEvent);
      expect(karma.length, 2);

      final cases = state.forType(NotificationType.caseAssignment);
      expect(cases.length, 1);
    });

    test('isTypeEnabled respects preferences', () {
      final state = NotificationState(
        preferences: const NotificationPreferences.allEnabled()
            .withType(NotificationType.karmaEvent, false),
      );

      expect(state.isTypeEnabled(NotificationType.karmaEvent), false);
      expect(state.isTypeEnabled(NotificationType.caseAssignment), true);
    });

    test('error state carries errorMessage', () {
      const state = NotificationState(
        phase: NotificationPhase.error,
        errorMessage: 'Unable to load notifications',
      );

      expect(state.phase, NotificationPhase.error);
      expect(state.errorMessage, 'Unable to load notifications');
      expect(state.notifications, isEmpty);
    });
  });
}
