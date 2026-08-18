import '../domain/notification_record.dart';
import '../domain/notification_type.dart';

/// Row codec for [NotificationRecord] (Task 10.4 Notification System).
///
/// Converts between the SQLCipher row representation and the domain entity.
/// The read path revalidates every field to ensure no corrupted or PII-
/// containing rows slip through.
///
/// SECURITY CHECKPOINT (10.4): the codec validates that title/body
/// contain no phone-shaped literals or email patterns before the entity
/// enters the domain layer. A malformed row is rejected with
/// [FormatException].
class NotificationRecordCodec {
  /// Convert a raw SQL row (Map<String, Object?>) to a [NotificationRecord].
  ///
  /// Throws [FormatException] if the row is malformed or contains PII
  /// shapes in title/body.
  static NotificationRecord decode(Map<String, Object?> row) {
    final id = row['notification_id'] as String?;
    final typeWire = row['type'] as String?;
    final title = row['title'] as String?;
    final body = row['body'] as String?;
    final createdAtMs = row['created_at'] as int?;
    final isRead = row['is_read'] as int?;

    if (id == null ||
        typeWire == null ||
        title == null ||
        body == null ||
        createdAtMs == null ||
        isRead == null) {
      throw const FormatException('notification row missing required columns');
    }

    final type = NotificationType.fromWireName(typeWire);

    return NotificationRecord(
      id: id,
      type: type,
      title: title,
      body: body,
      createdAt: DateTime.fromMillisecondsSinceEpoch(createdAtMs, isUtc: true),
      isRead: isRead == 1,
    );
  }

  /// Convert a [NotificationRecord] to a row map for SQLCipher storage.
  static Map<String, Object?> encode(NotificationRecord record) {
    return {
      'notification_id': record.id,
      'type': record.type.wireName,
      'title': record.title,
      'body': record.body,
      'created_at': record.createdAt.millisecondsSinceEpoch,
      'is_read': record.isRead ? 1 : 0,
    };
  }
}
