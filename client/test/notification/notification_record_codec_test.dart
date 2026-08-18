import 'package:civic_commons/notification/data/notification_record_codec.dart';
import 'package:civic_commons/notification/domain/notification_record.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationRecordCodec', () {
    test('encode/decode round-trip preserves all fields', () {
      final original = NotificationRecord(
        id: 'notif-001',
        type: NotificationType.karmaEvent,
        title: 'Karma +5',
        body: 'Your Ledger post was verified.',
        createdAt: DateTime.utc(2026, 8, 18, 10, 30),
        isRead: true,
      );

      final row = NotificationRecordCodec.encode(original);
      final decoded = NotificationRecordCodec.decode(row);

      expect(decoded.id, original.id);
      expect(decoded.type, original.type);
      expect(decoded.title, original.title);
      expect(decoded.body, original.body);
      expect(decoded.createdAt, original.createdAt);
      expect(decoded.isRead, original.isRead);
    });

    test('decode respects is_read flag (0 = unread)', () {
      final row = {
        'notification_id': 'notif-002',
        'type': 'case_assignment',
        'title': 'Case assigned',
        'body': 'CC-0047.',
        'created_at': DateTime.utc(2026, 8, 18, 9).millisecondsSinceEpoch,
        'is_read': 0,
      };

      final decoded = NotificationRecordCodec.decode(row);
      expect(decoded.isRead, false);
    });

    test('decode respects is_read flag (1 = read)', () {
      final row = {
        'notification_id': 'notif-003',
        'type': 'ledger_review_request',
        'title': 'Review needed',
        'body': 'Peer review.',
        'created_at': DateTime.utc(2026, 8, 18, 8).millisecondsSinceEpoch,
        'is_read': 1,
      };

      final decoded = NotificationRecordCodec.decode(row);
      expect(decoded.isRead, true);
    });

    test('decode throws FormatException for missing columns', () {
      final row = <String, Object?>{
        'notification_id': 'notif-004',
        // missing type, title, body, created_at, is_read
      };

      expect(
        () => NotificationRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for unknown type wire code', () {
      final row = {
        'notification_id': 'notif-005',
        'type': 'unknown_type',
        'title': 'Test',
        'body': 'Test body.',
        'created_at': DateTime.utc(2026, 8, 18, 8).millisecondsSinceEpoch,
        'is_read': 0,
      };

      expect(
        () => NotificationRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('encode produces correct column names', () {
      final record = NotificationRecord(
        id: 'notif-006',
        type: NotificationType.ledgerReviewRequest,
        title: 'Review',
        body: 'Please review.',
        createdAt: DateTime.utc(2026, 8, 18, 12),
      );

      final row = NotificationRecordCodec.encode(record);
      expect(row.containsKey('notification_id'), true);
      expect(row.containsKey('type'), true);
      expect(row.containsKey('title'), true);
      expect(row.containsKey('body'), true);
      expect(row.containsKey('created_at'), true);
      expect(row.containsKey('is_read'), true);
      expect(row['is_read'], 0); // unread
    });
  });
}
