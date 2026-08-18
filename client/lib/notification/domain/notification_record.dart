import 'notification_type.dart';

/// An immutable notification entity (Task 10.4 Notification System).
///
/// Carries only the minimum public data needed to render the notification
/// in the history viewer: a UUID v4 id, the fixed [NotificationType], a
/// short title + body string (public labels only), a timestamp, and a
/// read/unread flag.
///
/// SECURITY CHECKPOINT (10.4):
/// - No raw blind hashes, no phone numbers, no identity fields.
/// - Title and body must be PUBLIC LABELS only (e.g. "Karma +5",
///   "Case CC-0047 assigned", "Review: Drainage repair deadline slips").
/// - The entity is immutable; read state is toggled via [withRead].
class NotificationRecord {
  /// UUID v4 identifier.
  final String id;

  /// The fixed notification type.
  final NotificationType type;

  /// Short public title (non-PII label).
  final String title;

  /// Longer public body text (non-PII).
  final String body;

  /// Timestamp when the notification was created.
  final DateTime createdAt;

  /// Whether the user has seen this notification.
  final bool isRead;

  const NotificationRecord({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    required this.createdAt,
    this.isRead = false,
  });

  /// Returns a copy with [isRead] toggled to true (mark-as-read).
  NotificationRecord withRead() => NotificationRecord(
        id: id,
        type: type,
        title: title,
        body: body,
        createdAt: createdAt,
        isRead: true,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NotificationRecord &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          isRead == other.isRead;

  @override
  int get hashCode => id.hashCode ^ isRead.hashCode;
}
