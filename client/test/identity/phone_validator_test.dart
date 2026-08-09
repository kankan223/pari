import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/identity/phone_validator.dart';

void main() {
  group('PhoneValidator - E.164 Validation', () {
    test('should validate correct E.164 phone numbers', () {
      // Valid E.164 phone numbers
      expect(PhoneValidator.isValidE164('+14155552671'), isTrue);
      expect(PhoneValidator.isValidE164('+442071234567'), isTrue);
      expect(PhoneValidator.isValidE164('+919876543210'), isTrue);
      expect(PhoneValidator.isValidE164('+1234567890'), isTrue);
    });

    test('should reject invalid E.164 phone numbers', () {
      // Invalid formats
      expect(PhoneValidator.isValidE164(''), isFalse); // Empty
      expect(PhoneValidator.isValidE164('14155552671'), isFalse); // Missing +
      expect(PhoneValidator.isValidE164('+04155552671'),
          isFalse); // Country code starts with 0
      expect(PhoneValidator.isValidE164('+1'), isFalse); // Too short
      expect(
          PhoneValidator.isValidE164('+1234567890123456'), isFalse); // Too long
      expect(PhoneValidator.isValidE164('+1415-555-2671'),
          isFalse); // Contains dashes
      expect(PhoneValidator.isValidE164('+1415 555 2671'),
          isFalse); // Contains spaces
      expect(
          PhoneValidator.isValidE164('(415) 555-2671'), isFalse); // Parentheses
    });

    test('should normalize phone numbers to E.164 format', () {
      // Normalize with country code
      expect(
        PhoneValidator.normalizeToE164('4155552671', countryCode: '1'),
        equals('+14155552671'),
      );
      expect(
        PhoneValidator.normalizeToE164('415-555-2671', countryCode: '1'),
        equals('+14155552671'),
      );
      expect(
        PhoneValidator.normalizeToE164('(415) 555-2671', countryCode: '1'),
        equals('+14155552671'),
      );

      // Already in E.164 format
      expect(
        PhoneValidator.normalizeToE164('+14155552671'),
        equals('+14155552671'),
      );

      // Invalid normalization
      expect(
        PhoneValidator.normalizeToE164('invalid'),
        isNull,
      );
    });

    test('should extract country code from E.164 phone number', () {
      expect(PhoneValidator.extractCountryCode('+14155552671'), equals('1'));
      expect(PhoneValidator.extractCountryCode('+442071234567'), equals('44'));
      expect(PhoneValidator.extractCountryCode('+919876543210'), equals('91'));
      expect(PhoneValidator.extractCountryCode('+1234567890'), equals('1'));
    });

    test(
        'should return null for invalid phone number when extracting country code',
        () {
      expect(PhoneValidator.extractCountryCode('14155552671'), isNull);
      expect(PhoneValidator.extractCountryCode(''), isNull);
      expect(PhoneValidator.extractCountryCode('invalid'), isNull);
    });

    test('should mask phone number for display', () {
      // Mask keeps the country code and the last 4 digits, masking the middle
      expect(
        PhoneValidator.maskForDisplay('+14155552671'),
        equals('+1******2671'),
      );
      expect(
        PhoneValidator.maskForDisplay('+442071234567'),
        equals('+44******4567'),
      );
      expect(
        PhoneValidator.maskForDisplay('+919876543210'),
        equals('+91******3210'),
      );
    });

    test('should mask without leaking more than the last 4 digits', () {
      // The masked output must never contain any of the masked middle digits
      final masked = PhoneValidator.maskForDisplay('+14155552671');
      expect(masked, isNot(contains('415555')));
      expect(masked, isNot(contains('+14155552671')));
    });

    test('should return Invalid for invalid phone number when masking', () {
      expect(
        PhoneValidator.maskForDisplay('invalid'),
        equals('Invalid'),
      );
      expect(
        PhoneValidator.maskForDisplay(''),
        equals('Invalid'),
      );
    });
  });
}
