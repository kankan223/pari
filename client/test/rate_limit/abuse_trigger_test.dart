import 'package:civic_commons/rate_limit/domain/abuse_trigger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AbuseTrigger', () {
    test('has 8 fixed triggers', () {
      expect(AbuseTrigger.values.length, 8);
    });

    test('fromWireName returns correct trigger', () {
      expect(AbuseTrigger.fromWireName('excessiveOtpRequests'),
          AbuseTrigger.excessiveOtpRequests);
      expect(AbuseTrigger.fromWireName('rapidLoginFailures'),
          AbuseTrigger.rapidLoginFailures);
      expect(AbuseTrigger.fromWireName('lockstepVoting'),
          AbuseTrigger.lockstepVoting);
      expect(AbuseTrigger.fromWireName('excessiveConnectionRequests'),
          AbuseTrigger.excessiveConnectionRequests);
      expect(AbuseTrigger.fromWireName('rapidPostCreation'),
          AbuseTrigger.rapidPostCreation);
      expect(AbuseTrigger.fromWireName('credentialStuffing'),
          AbuseTrigger.credentialStuffing);
      expect(AbuseTrigger.fromWireName('apiAbuse'),
          AbuseTrigger.apiAbuse);
      expect(AbuseTrigger.fromWireName('accountEnumeration'),
          AbuseTrigger.accountEnumeration);
    });

    test('fromWireName throws on unknown', () {
      expect(
        () => AbuseTrigger.fromWireName('unknown'),
        throwsFormatException,
      );
    });

    test('labels are non-empty', () {
      for (final trigger in AbuseTrigger.values) {
        expect(trigger.label, isNotEmpty);
        expect(trigger.description, isNotEmpty);
      }
    });

    test('each trigger has a severity', () {
      for (final trigger in AbuseTrigger.values) {
        expect(trigger.severity, isNotNull);
      }
    });
  });

  group('AbuseSeverity', () {
    test('has 4 fixed severities', () {
      expect(AbuseSeverity.values.length, 4);
    });

    test('fromWireName returns correct severity', () {
      expect(AbuseSeverity.fromWireName('low'), AbuseSeverity.low);
      expect(AbuseSeverity.fromWireName('medium'), AbuseSeverity.medium);
      expect(AbuseSeverity.fromWireName('high'), AbuseSeverity.high);
      expect(AbuseSeverity.fromWireName('critical'), AbuseSeverity.critical);
    });

    test('fromWireName throws on unknown', () {
      expect(
        () => AbuseSeverity.fromWireName('unknown'),
        throwsFormatException,
      );
    });

    test('labels are non-empty', () {
      for (final severity in AbuseSeverity.values) {
        expect(severity.label, isNotEmpty);
        expect(severity.shortLabel, isNotEmpty);
      }
    });
  });

  group('AbuseEvent', () {
    test('equality based on eventId', () {
      final e1 = AbuseEvent(
        eventId: 'event-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: DateTime.utc(2026, 8, 19),
        occurrenceCount: 5,
      );
      final e2 = AbuseEvent(
        eventId: 'event-1',
        trigger: AbuseTrigger.rapidLoginFailures,
        detectedAt: DateTime.utc(2026, 8, 20),
        occurrenceCount: 10,
      );
      expect(e1, equals(e2));

      final e3 = AbuseEvent(
        eventId: 'event-2',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: DateTime.utc(2026, 8, 19),
        occurrenceCount: 5,
      );
      expect(e1, isNot(equals(e3)));
    });

    test('hashCode based on eventId', () {
      final e1 = AbuseEvent(
        eventId: 'event-1',
        trigger: AbuseTrigger.excessiveOtpRequests,
        detectedAt: DateTime.utc(2026, 8, 19),
        occurrenceCount: 5,
      );
      final e2 = AbuseEvent(
        eventId: 'event-1',
        trigger: AbuseTrigger.rapidLoginFailures,
        detectedAt: DateTime.utc(2026, 8, 20),
        occurrenceCount: 10,
      );
      expect(e1.hashCode, equals(e2.hashCode));
    });
  });
}
