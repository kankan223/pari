import 'push_notification_service_stub.dart'
    if (dart.library.html) 'push_notification_service_web.dart';

/// Service for browser push notifications using the Web Notification API.
///
/// Shows browser notifications when the app is in the background and a new
/// message arrives via WebSocket. Tapping the notification focuses the window.
///
/// SECURITY CHECKPOINT: notifications contain only display name + truncated
/// message preview — never phone numbers, blind hashes, or tokens.
abstract class PushNotificationService {
  /// Whether permission has been granted.
  bool get hasPermission;

  /// Initialize: check browser support and request permission.
  Future<bool> initialize();

  /// Show a notification for a new incoming message.
  void showMessageNotification({
    required String senderName,
    required String preview,
    String? conversationId,
  });

  /// Show a generic notification.
  void showNotification({
    required String title,
    required String body,
    String? tag,
  });

  /// Factory constructor that returns the platform-specific implementation.
  factory PushNotificationService() => createPushNotificationService();
}
