import 'push_notification_service.dart';

/// Stub implementation for non-web platforms (mobile, desktop).
/// Notifications are not supported on these platforms via this service.
class StubPushNotificationService implements PushNotificationService {
  @override
  bool get hasPermission => false;

  @override
  Future<bool> initialize() async => false;

  @override
  void showMessageNotification({
    required String senderName,
    required String preview,
    String? conversationId,
  }) {}

  @override
  void showNotification({
    required String title,
    required String body,
    String? tag,
  }) {}
}

PushNotificationService createPushNotificationService() =>
    StubPushNotificationService();
