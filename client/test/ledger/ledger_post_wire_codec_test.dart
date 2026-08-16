import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/ledger/domain/ledger_category.dart';
import 'package:civic_commons/ledger/domain/ledger_post_wire_codec.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LedgerPostWireFrame codec (Task 7.4)', () {
    test('encode -> decode round-trips every civic field exactly', () {
      const frame = LedgerPostWireFrame(
        category: LedgerCategory.civicInfrastructure,
        pinCode: '800001',
        headline: 'Boring Road drainage',
        body: 'Third week stopped.',
      );

      final restored = decodeLedgerPostFrame(encodeLedgerPostFrame(frame));

      expect(restored.category, LedgerCategory.civicInfrastructure);
      expect(restored.pinCode, '800001');
      expect(restored.headline, 'Boring Road drainage');
      expect(restored.body, 'Third week stopped.');
    });

    test('round-trips ALL categories (wire names are stable)', () {
      for (final category in LedgerCategory.values) {
        final frame = LedgerPostWireFrame(
          category: category,
          pinCode: '560001',
          headline: 'H',
          body: '',
        );
        final restored = decodeLedgerPostFrame(encodeLedgerPostFrame(frame));
        expect(restored.category, category,
            reason: '${category.wireName} must round-trip');
      }
    });

    test('wire frame carries ONLY civic fields — never identity', () {
      const frame = LedgerPostWireFrame(
        category: LedgerCategory.studentRights,
        pinCode: '800001',
        headline: 'H',
        body: 'B',
      );
      final json = frame.toJson();

      // No author, no blind hash, no phone, no device id — just the four
      // public civic fields plus the version tag.
      expect(
          json.keys.toSet(), {'v', 'category', 'pin_code', 'headline', 'body'});
      expect(json.values.join(',').toLowerCase(), isNot(contains('hash')));
      expect(json.values.join(',').toLowerCase(), isNot(contains('phone')));
    });

    test('empty body round-trips (body is optional)', () {
      const frame = LedgerPostWireFrame(
        category: LedgerCategory.satireAndCulture,
        pinCode: '800001',
        headline: 'H',
      );

      final restored = decodeLedgerPostFrame(encodeLedgerPostFrame(frame));

      expect(restored.body, isEmpty);
    });

    test('decode rejects an unknown category wire name (strict bounds)', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({
          'v': 1,
          'category': 'crypto_scam',
          'pin_code': '800001',
          'headline': 'H',
        }),
      ));

      expect(() => decodeLedgerPostFrame(bytes), throwsArgumentError);
    });

    test('decode rejects an unsupported wire version', () {
      final bytes = Uint8List.fromList(utf8.encode(
        jsonEncode({
          'v': 99,
          'category': 'breaking_local',
          'pin_code': '800001',
          'headline': 'H',
        }),
      ));

      expect(() => decodeLedgerPostFrame(bytes), throwsArgumentError);
    });

    test('decode rejects non-object / malformed payloads', () {
      final arrayBytes = Uint8List.fromList(utf8.encode('[1,2,3]'));
      expect(() => decodeLedgerPostFrame(arrayBytes),
          throwsA(isA<FormatException>()));

      final garbage = Uint8List.fromList([0xff, 0xfe, 0x01]);
      expect(() => decodeLedgerPostFrame(garbage), throwsFormatException);
    });

    test('the encoded frame is deterministic for identical drafts', () {
      LedgerPostWireFrame build() => const LedgerPostWireFrame(
            category: LedgerCategory.breakingLocal,
            pinCode: '110001',
            headline: 'H',
            body: 'B',
          );

      final a = encodeLedgerPostFrame(build());
      final b = encodeLedgerPostFrame(build());

      expect(a, equals(b));
    });
  });
}
