import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/security/domain/root_detection_service.dart';
import 'package:civic_commons/security/domain/security_policy.dart';

void main() {
  const policy = DeviceSecurityPolicy();

  group('DeviceSecurityPolicy - clean device', () {
    test('returns a normal decision and allows continuation', () {
      final decision = policy.evaluate(DeviceIntegrity.clean);

      expect(decision.severity, SecuritySeverity.normal);
      expect(decision.allowsContinue, isTrue);
      expect(decision.triggeredChecks, isEmpty);
    });
  });

  group('DeviceSecurityPolicy - rooted device', () {
    test('returns a warning decision but NEVER blocks (allowsContinue)', () {
      const integrity = DeviceIntegrity(
        isRooted: true,
        isJailbroken: false,
        triggeredChecks: [RootCheck.suBinaryPresent],
      );

      final decision = policy.evaluate(integrity);

      expect(decision.severity, SecuritySeverity.warning);
      expect(decision.allowsContinue, isTrue, reason: 'Warning, not block');
      expect(decision.triggeredChecks, contains(RootCheck.suBinaryPresent));
    });

    test('surfaces all triggered checks in the warning', () {
      const integrity = DeviceIntegrity(
        isRooted: true,
        isJailbroken: false,
        triggeredChecks: [
          RootCheck.suBinaryPresent,
          RootCheck.knownRootPackage,
          RootCheck.testKeysBuildTag,
        ],
      );

      final decision = policy.evaluate(integrity);

      expect(decision.severity, SecuritySeverity.warning);
      expect(decision.triggeredChecks, hasLength(3));
    });
  });

  group('DeviceSecurityPolicy - jailbroken device', () {
    test('returns a warning decision without blocking', () {
      const integrity = DeviceIntegrity(
        isRooted: false,
        isJailbroken: true,
        triggeredChecks: [RootCheck.writableSystemPath],
      );

      final decision = policy.evaluate(integrity);

      expect(decision.severity, SecuritySeverity.warning);
      expect(decision.allowsContinue, isTrue);
    });
  });

  group('DeviceSecurityPolicy - SECURITY CHECKPOINT', () {
    test('policy is pure logic: no telemetry, no fingerprinting data emitted',
        () {
      // The decision carries only a severity and generic check enums — no
      // device identifiers (serial, model, Android ID, locale, MAC, etc.).
      const integrity = DeviceIntegrity(
        isRooted: true,
        isJailbroken: false,
        triggeredChecks: [RootCheck.knownRootPackage],
      );

      final decision = policy.evaluate(integrity);

      expect(decision.severity, SecuritySeverity.warning);
      // The only data present is the generic check enum.
      expect(decision.triggeredChecks, [RootCheck.knownRootPackage]);
      // No printable identifiers are part of the decision type.
      final stringified = decision.toString();
      expect(stringified, isNot(contains('serial')));
      expect(stringified, isNot(contains('imei')));
      expect(stringified, isNot(contains('androidId')));
      expect(stringified, isNot(contains('model')));
    });
  });
}
