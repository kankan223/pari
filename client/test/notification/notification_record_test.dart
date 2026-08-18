import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationRecord', () {
    test('constructs with required fields', () {
      final record = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'Karma +5',
        body: 'Your Ledger post was verified.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );

      expect(record.id, 'notif-001');
      expect(record.type, NotificationType.karmaEvent);
      expect(record.title, 'Karma +5');
      expect(record.body, 'Your Ledger post was verified.');
      expect(record.isRead, false);
    });

    test('withRead returns a copy with isRead true', () {
      final record = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.caseAssignment,
        title: 'Case assigned',
        body: 'CC-0047 assigned.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );

      final read = record.withRead();
      expect(read.isRead, true);
      expect(read.id, record.id);
      expect(read.type, record.type);
      expect(read.title, record.title);
      expect(read.body, record.body);
      expect(read.createdAt, record.createdAt);
    });

    test('original is unchanged after withRead', () {
      final record = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.ledgerReviewRequest,
        title: 'Review needed',
        body: 'Peer review required.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );

      record.withRead();
      expect(record.isRead, false);
    });

    test('equality is based on id and isRead', () {
      final a = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'Karma +5',
        body: 'Verified.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );
      final b = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'Karma +5',
        body: 'Verified.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
        isRead: true,
      );

      // Same id but different isRead → not equal
      expect(a == b, false);
    });

    test('same id and isRead are equal', () {
      final a = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'Karma +5',
        body: 'Verified.',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );
      final b = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.caseAssignment,
        title: 'Different title',
        body: 'Different body.',
        createdAt: DateTime.utc(2026, 8, 19, 10),
      );

      // Same id, both unread → equal (equality only checks id + isRead)
      expect(a == b, true);
    });

    test('different ids are not equal', () {
      final a = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'A',
        body: 'A',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );
      final b = NotificationRecord(
        id: 'notif-002',
        type: NotificationType.karmaEvent,
        title: 'A',
        body: 'A',
        createdAt: DateTime.utc(2026, 8, 18, 10),
      );

      expect(a == b, false);
    });
  });
}
