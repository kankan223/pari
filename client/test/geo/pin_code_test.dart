import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PinCode (Task 7.2)', () {
    test('accepts valid 6-digit pins', () {
      expect(PinCode.tryParse('800001'), isNotNull);
      expect(PinCode.tryParse('560001'), isNotNull);
      expect(PinCode.tryParse('110001'), isNotNull);
      expect(PinCode.tryParse(' 400001 '), isNotNull); // trimmed
    });

    test('rejects malformed pins', () {
      // Not 6 digits.
      expect(PinCode.tryParse('80001'), isNull);
      expect(PinCode.tryParse('8000011'), isNull);
      expect(PinCode.tryParse(''), isNull);
      // Leading zero (Indian pins never start with 0).
      expect(PinCode.tryParse('080001'), isNull);
      // Non-digits.
      expect(PinCode.tryParse('8000a1'), isNull);
      expect(PinCode.tryParse('8000 1'), isNull);
    });

    test('parse throws ArgumentError on malformed input', () {
      expect(() => PinCode.parse('12'), throwsArgumentError);
      expect(PinCode.parse('800001').value, '800001');
    });

    test('circlePrefix exposes the coarse postal circle', () {
      expect(PinCode.parse('800001').circlePrefix, '80');
      expect(PinCode.parse('560001').circlePrefix, '56');
    });

    test('equality is by value', () {
      expect(PinCode.parse('800001'), PinCode.parse('800001'));
      expect(PinCode.parse('800001'), isNot(PinCode.parse('800002')));
    });

    test('a PinCode can never encode finer-than-pin location', () {
      // The value space is exactly 6 digits — no lat/lng/address can fit.
      for (final raw in [
        '25.61,85.14',
        'Boring Road, Patna',
        '25.6100',
      ]) {
        expect(PinCode.tryParse(raw), isNull);
      }
    });
  });
}
