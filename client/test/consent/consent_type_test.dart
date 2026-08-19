import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsentType', () {
    test('has exactly five consent types', () {
      expect(ConsentType.values.length, 5);
    });

    test('wire round-trip for every type', () {
      for (final type in ConsentType.values) {
        final decoded = ConsentType.fromWireName(type.wireName);
        expect(decoded, type);
      }
    });

    test('labels and descriptions are non-empty', () {
      for (final type in ConsentType.values) {
        expect(type.label.isNotEmpty, true);
        expect(type.description.isNotEmpty, true);
      }
    });

    test('unknown wire name throws FormatException', () {
      expect(
        () => ConsentType.fromWireName('unknown_type'),
        throwsFormatException,
      );
    });

    test('empty wire name throws FormatException', () {
      expect(
        () => ConsentType.fromWireName(''),
        throwsFormatException,
      );
    });
  });
}
