import '../../notification/domain/notification_record.dart';
import '../../notification/domain/notification_preferences.dart';
import '../../notification/domain/notification_type.dart';

/// Notification system phases (Task 10.4).
enum NotificationPhase {
  /// Not started.
  idle,

  /// Reading the local notification store.
  loading,

  /// Notifications + preferences are projected.
  ready,

  /// A local source failed — generic, payload-free error.
  error,
}

/// Immutable state projection for the Notification System (Task 10.4).
///
/// Carries the notifications list (newest first), unread count, and the
/// current preferences. The UI reads from this state and calls the BLoC
/// to trigger transitions.
///
/// SECURITY CHECKPOINT (10.4):
/// - [notifications] contains only [NotificationRecord] objects with
///   public-label title/body — no blind hashes, no identity, no PII.
/// - [preferences] carries only boolean flags keyed by fixed type codes.
/// - The error state carries no payload (generic message only).
class NotificationState {
  final NotificationPhase phase;
  final List<NotificationRecord> notifications;
  final int unreadCount;
  final NotificationPreferences preferences;
  final String? errorMessage;

  const NotificationState({
    this.phase = NotificationPhase.idle,
    this.notifications = const [],
    this.unreadCount = 0,
    this.preferences = const NotificationPreferences.allEnabled(),
    this.errorMessage,
  });

  /// Convenience: is [type] enabled in the current preferences?
  bool isTypeEnabled(NotificationType type) => preferences.isEnabled(type);

  /// Convenience: filtered notifications for a specific type.
  List<NotificationRecord> forType(NotificationType type) =>
      notifications.where((n) => n.type == type).toList(growable: false);
}
