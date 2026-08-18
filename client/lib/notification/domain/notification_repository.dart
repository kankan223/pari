import 'notification_preferences.dart';
import 'notification_record.dart';
import 'notification_type.dart';

/// Repository port for the Notification System (Task 10.4).
///
/// All operations are local-first and offline-safe. The repository
/// interface carries NO identity — callers provide notification data
/// as pre-built [NotificationRecord] objects containing only public labels.
///
/// SECURITY CHECKPOINT (10.4):
/// - No raw blind hashes, no phone numbers, no identity fields in the
///   repository contract.
/// - Preferences are stored locally and never leave the device.
abstract class NotificationRepository {
  /// Returns all notifications, newest first.
  Future<List<NotificationRecord>> getAll();

  /// Returns notifications filtered by type, newest first.
  Future<List<NotificationRecord>> getByType(NotificationType type);

  /// Returns the count of unread notifications.
  Future<int> getUnreadCount();

  /// Marks a notification as read by its [id].
  Future<void> markRead(String id);

  /// Marks all notifications as read.
  Future<void> markAllRead();

  /// Inserts a new notification. The caller is responsible for providing
  /// a UUID v4 [id] and public-label-only [title]/[body].
  Future<void> insert(NotificationRecord record);

  /// Returns the current notification preferences.
  Future<NotificationPreferences> getPreferences();

  /// Persists updated notification preferences.
  Future<void> savePreferences(NotificationPreferences prefs);
}
