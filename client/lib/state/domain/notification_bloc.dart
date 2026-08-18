import '../../notification/domain/notification_preferences.dart';
import 'notification_state.dart';

/// BLoC for the Notification System (Task 10.4).
///
/// The UI binds to [state] and calls [refresh]/[markRead]/[markAllRead]/
/// [savePreferences] — it never talks to the notification repository directly.
///
/// SECURITY CHECKPOINT (10.4): [NotificationState] carries only the public
/// notifications list (public-label title/body) + unread count + boolean
/// preferences. No blind hash, no identity, no PII can appear in state;
/// error states carry no payload at all.
abstract class NotificationBloc {
  /// Stream of notification states (idle → loading → ready | error).
  Stream<NotificationState> get state;

  /// The current state (for late subscribers).
  NotificationState get current;

  /// Re-reads the notification store and projects the list + unread count.
  Future<void> refresh();

  /// Marks a notification as read by its [id].
  Future<void> markRead(String id);

  /// Marks all notifications as read.
  Future<void> markAllRead();

  /// Persists updated notification preferences.
  Future<void> savePreferences(NotificationPreferences prefs);

  /// Releases resources.
  Future<void> close();
}
