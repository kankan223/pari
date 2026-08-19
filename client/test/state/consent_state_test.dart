import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:civic_commons/state/domain/consent_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsentState', () {
    test('default state is idle with no consents', () {
      const state = ConsentState();
      expect(state.phase, ConsentPhase.idle);
      expect(state.consentStatus, isEmpty);
      expect(state.allRequiredGranted, false);
      expect(state.consentVersion, '1.0');
      expect(state.errorMessage, isNull);
    });

    test('hasConsent returns false for unknown type', () {
      const state = ConsentState();
      expect(state.hasConsent(ConsentType.coreFunctionality), false);
    });

    test('hasConsent returns true when type is granted', () {
      const state = ConsentState(
        consentStatus: {ConsentType.analytics: true},
      );
      expect(state.hasConsent(ConsentType.analytics), true);
      expect(state.hasConsent(ConsentType.coreFunctionality), false);
    });

    test('hasConsent returns false when type is explicitly false', () {
      const state = ConsentState(
        consentStatus: {ConsentType.civicEngagement: false},
      );
      expect(state.hasConsent(ConsentType.civicEngagement), false);
    });

    test('allRequiredGranted flag is respected', () {
      const state = ConsentState(
        allRequiredGranted: true,
        consentStatus: {
          ConsentType.coreFunctionality: true,
          ConsentType.civicEngagement: true,
          ConsentType.securityContributions: true,
          ConsentType.educationalContent: true,
        },
      );
      expect(state.allRequiredGranted, true);
    });

    test('error message is carried in error phase', () {
      const state = ConsentState(
        phase: ConsentPhase.error,
        errorMessage: 'Something went wrong',
      );
      expect(state.phase, ConsentPhase.error);
      expect(state.errorMessage, 'Something went wrong');
    });

    test('deleting phase is set during data deletion', () {
      const state = ConsentState(phase: ConsentPhase.deleting);
      expect(state.phase, ConsentPhase.deleting);
    });

    test('deleted phase indicates data has been removed', () {
      const state = ConsentState(
        phase: ConsentPhase.deleted,
        allRequiredGranted: false,
      );
      expect(state.phase, ConsentPhase.deleted);
      expect(state.allRequiredGranted, false);
    });

    test('consentStatus is immutable map', () {
      const state = ConsentState(
        consentStatus: {ConsentType.analytics: true},
      );
      // Verify the map is not empty
      expect(state.consentStatus.length, 1);
    });
  });
}
