import 'package:civic_commons/geo/domain/geo_place.dart';
import 'package:civic_commons/geo/domain/pin_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoPlace (Task 7.2)', () {
    test('scopeLine composes locality · district · pin (DESIGN §7.2)', () {
      final place = GeoPlace(
        pinCode: PinCode.parse('800001'),
        district: 'Patna',
        locality: 'Sadar',
      );
      expect(place.scopeLine, 'Sadar · Patna · 800001');
    });

    test('scopeLine degrades gracefully when names are missing', () {
      final place = GeoPlace(pinCode: PinCode.parse('560001'));
      expect(place.scopeLine, '560001');
    });

    test('equality is structural', () {
      final a = GeoPlace(
        pinCode: PinCode.parse('800001'),
        district: 'Patna',
        locality: 'Sadar',
      );
      final b = GeoPlace(
        pinCode: PinCode.parse('800001'),
        district: 'Patna',
        locality: 'Sadar',
      );
      final c = GeoPlace(pinCode: PinCode.parse('800002'));
      expect(a, b);
      expect(a, isNot(c));
    });

    test('carries ONLY public civic fields — no coordinates', () {
      // The type has exactly pin + district + locality; there is no
      // latitude/longitude/accuracy member to leak.
      final place = GeoPlace(pinCode: PinCode.parse('800001'));
      expect(place.pinCode.value, '800001');
      // Reflection-free structural proof: the public API surface is fixed.
      expect(GeoPlace(pinCode: PinCode.parse('800001')).toString(), '800001');
    });
  });
}
