// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js' as js;

import 'push_notification_service.dart';

/// Web implementation using the browser Notification API.
///
/// SECURITY CHECKPOINT: notifications contain only display name + truncated
/// message preview — never phone numbers, blind hashes, or tokens.
class WebPushNotificationService implements PushNotificationService {
  bool _hasPermission = false;

  @override
  bool get hasPermission => _hasPermission;

  @override
  Future<bool> initialize() async {
    if (!html.Notification.supported) return false;

    final perm = html.Notification.permission;
    if (perm == 'granted') {
      _hasPermission = true;
      return true;
    }
    if (perm == 'denied') return false;

    final result = await html.Notification.requestPermission();
    _hasPermission = result == 'granted';
    return _hasPermission;
  }

  /// Returns true if the document is hidden (tab not focused).
  bool _isPageHidden() {
    try {
      return js.context['document']['hidden']?.toString() == 'true';
    } catch (_) {
      return false;
    }
  }

  @override
  void showMessageNotification({
    required String senderName,
    required String preview,
    String? conversationId,
  }) {
    if (!_hasPermission) return;
    if (!_isPageHidden()) return;

    try {
      final notification = html.Notification(
        senderName,
        body: preview,
        tag: 'message-$conversationId',
      );
      notification.onClick.listen((_) {
        js.context.callMethod('eval', ['window.focus()']);
      });
    } catch (_) {
      // Best-effort.
    }
  }

  @override
  void showNotification({
    required String title,
    required String body,
    String? tag,
  }) {
    if (!_hasPermission) return;
    if (!_isPageHidden()) return;

    try {
      html.Notification(title, body: body, tag: tag);
    } catch (_) {
      // Best-effort.
    }
  }
}

PushNotificationService createPushNotificationService() =>
    WebPushNotificationService();
