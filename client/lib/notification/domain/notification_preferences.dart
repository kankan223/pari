import 'notification_type.dart';

/// User notification preferences (Task 10.4 Notification System).
///
/// Stores per-[NotificationType] enable/disable flags. All three types
/// default to enabled. The preferences are stored locally and never
/// leave the device (offline-first, zero-PII).
///
/// SECURITY CHECKPOINT (10.4): preferences carry only boolean flags keyed
/// by the fixed wire names — no identity, no PII, no tokens.
class NotificationPreferences {
  final Map<NotificationType, bool> _enabled;

  const NotificationPreferences._(this._enabled);

  /// All types enabled (the production default).
  const NotificationPreferences.allEnabled()
      : _enabled = const {
          NotificationType.karmaEvent: true,
          NotificationType.caseAssignment: true,
          NotificationType.ledgerReviewRequest: true,
        };

  /// Whether notifications of [type] are enabled.
  bool isEnabled(NotificationType type) => _enabled[type] ?? true;

  /// Returns a copy with [type] set to [enabled].
  NotificationPreferences withType(NotificationType type, bool enabled) {
    return NotificationPreferences._({..._enabled, type: enabled});
  }

  /// Returns a copy with all types set to [enabled].
  NotificationPreferences withAll(bool enabled) {
    return NotificationPreferences._({
      for (final t in NotificationType.values) t: enabled,
    });
  }

  /// Wire-safe map for serialization.
  Map<String, bool> toWire() => {
        for (final t in NotificationType.values) t.wireName: isEnabled(t),
      };

  /// Reconstruct from a wire map (unknown keys ignored).
  factory NotificationPreferences.fromWire(Map<String, bool> wire) {
    final map = <NotificationType, bool>{
      NotificationType.karmaEvent: wire['karma_event'] ?? true,
      NotificationType.caseAssignment: wire['case_assignment'] ?? true,
      NotificationType.ledgerReviewRequest:
          wire['ledger_review_request'] ?? true,
    };
    return NotificationPreferences._(map);
  }
}
