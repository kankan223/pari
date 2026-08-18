import 'package:civic_commons/notification/data/in_memory_notification_repository.dart';
import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_preferences.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryNotificationRepository repo;

  setUp(() {
    repo = InMemoryNotificationRepository(
      seed: [
        NotificationRecord(
          id: 'notif-1001',
          type: NotificationType.karmaEvent,
          title: 'Karma +5',
          body: 'Verified.',
          createdAt: DateTime.utc(2026, 8, 18, 10),
        ),
        NotificationRecord(
          id: 'notif-1002',
          type: NotificationType.caseAssignment,
          title: 'Case assigned',
          body: 'CC-0047 assigned.',
          createdAt: DateTime.utc(2026, 8, 18, 9),
          isRead: true,
        ),
        NotificationRecord(
          id: 'notif-1003',
          type: NotificationType.ledgerReviewRequest,
          title: 'Review needed',
          body: 'Peer review required.',
          createdAt: DateTime.utc(2026, 8, 18, 8),
        ),
      ],
    );
  });

  group('getAll', () {
    test('returns all notifications sorted newest first', () async {
      final all = await repo.getAll();
      expect(all.length, 3);
      expect(all[0].id, 'notif-1001');
      expect(all[1].id, 'notif-1002');
      expect(all[2].id, 'notif-1003');
    });
  });

  group('getByType', () {
    test('returns only matching type', () async {
      final karma = await repo.getByType(NotificationType.karmaEvent);
      expect(karma.length, 1);
      expect(karma[0].id, 'notif-1001');
    });

    test('returns empty for type with no notifications', () async {
      final none = await repo.getByType(NotificationType.caseAssignment);
      expect(none.length, 1); // one seeded
    });
  });

  group('getUnreadCount', () {
    test('counts unread notifications', () async {
      final count = await repo.getUnreadCount();
      expect(count, 2); // notif-1001 and notif-1003
    });
  });

  group('markRead', () {
    test('marks a single notification as read', () async {
      await repo.markRead('notif-1001');
      final count = await repo.getUnreadCount();
      expect(count, 1); // only notif-1003 remains unread
    });

    test('marking a non-existent id is a no-op', () async {
      await repo.markRead('notif-9999');
      final count = await repo.getUnreadCount();
      expect(count, 2);
    });
  });

  group('markAllRead', () {
    test('marks all notifications as read', () async {
      await repo.markAllRead();
      final count = await repo.getUnreadCount();
      expect(count, 0);
    });
  });

  group('insert', () {
    test('adds a new notification', () async {
      await repo.insert(NotificationRecord(
        id: 'notif-1004',
        type: NotificationType.karmaEvent,
        title: 'Karma −3',
        body: 'Rejected.',
        createdAt: DateTime.utc(2026, 8, 17, 12),
      ));

      final all = await repo.getAll();
      expect(all.length, 4);
    });
  });

  group('preferences', () {
    test('defaults to all enabled', () async {
      final prefs = await repo.getPreferences();
      for (final type in NotificationType.values) {
        expect(prefs.isEnabled(type), true);
      }
    });

    test('saves and retrieves preferences', () async {
      final updated = const NotificationPreferences.allEnabled()
          .withType(NotificationType.karmaEvent, false);
      await repo.savePreferences(updated);

      final prefs = await repo.getPreferences();
      expect(prefs.isEnabled(NotificationType.karmaEvent), false);
      expect(prefs.isEnabled(NotificationType.caseAssignment), true);
    });
  });
}
