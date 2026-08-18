import 'package:civic_commons/notification/domain/notification_preferences.dart';
import 'package:civic_commons/notification/domain/notification_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NotificationPreferences', () {
    test('allEnabled enables all three types', () {
      const prefs = NotificationPreferences.allEnabled();
      for (final type in NotificationType.values) {
        expect(prefs.isEnabled(type), true);
      }
    });

    test('withType disables a single type', () {
      const prefs = NotificationPreferences.allEnabled();
      final updated = prefs.withType(NotificationType.karmaEvent, false);

      expect(updated.isEnabled(NotificationType.karmaEvent), false);
      expect(updated.isEnabled(NotificationType.caseAssignment), true);
      expect(updated.isEnabled(NotificationType.ledgerReviewRequest), true);
    });

    test('withType enables a previously disabled type', () {
      const prefs = NotificationPreferences.allEnabled();
      final disabled = prefs.withType(NotificationType.karmaEvent, false);
      final reenabled = disabled.withType(NotificationType.karmaEvent, true);

      expect(reenabled.isEnabled(NotificationType.karmaEvent), true);
    });

    test('withAll disables everything', () {
      const prefs = NotificationPreferences.allEnabled();
      final disabled = prefs.withAll(false);

      for (final type in NotificationType.values) {
        expect(disabled.isEnabled(type), false);
      }
    });

    test('withAll enables everything', () {
      const prefs = NotificationPreferences.allEnabled();
      final disabled = prefs.withAll(false);
      final reenabled = disabled.withAll(true);

      for (final type in NotificationType.values) {
        expect(reenabled.isEnabled(type), true);
      }
    });

    test('toWire round-trips through fromWire', () {
      const prefs = NotificationPreferences.allEnabled();
      final disabled = prefs
          .withType(NotificationType.karmaEvent, false)
          .withType(NotificationType.ledgerReviewRequest, false);
      final wire = disabled.toWire();
      final restored = NotificationPreferences.fromWire(wire);

      expect(restored.isEnabled(NotificationType.karmaEvent), false);
      expect(restored.isEnabled(NotificationType.caseAssignment), true);
      expect(restored.isEnabled(NotificationType.ledgerReviewRequest), false);
    });

    test('fromWire defaults unknown keys to true', () {
      final wire = {
        'karma_event': false,
        'unknown_key': true,
      };
      final prefs = NotificationPreferences.fromWire(wire);

      expect(prefs.isEnabled(NotificationType.karmaEvent), false);
      expect(prefs.isEnabled(NotificationType.caseAssignment), true);
      expect(prefs.isEnabled(NotificationType.ledgerReviewRequest), true);
    });

    test('fromWire empty map enables all (defaults)', () {
      final prefs = NotificationPreferences.fromWire({});
      for (final type in NotificationType.values) {
        expect(prefs.isEnabled(type), true);
      }
    });
  });
}
