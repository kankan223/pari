import 'package:civic_commons/pairing/data/qr_codec_impl.dart';
import 'package:civic_commons/pairing/domain/qr_matrix.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('QrCodecEncoder (production `qr` package)', () {
    const encoder = QrCodecEncoder();

    test('encodes a payload into a square QR matrix', () {
      final matrix = encoder.encode('civic-commons://pair?v=1&bh=test');

      expect(matrix.moduleCount, greaterThan(0));
      // QR version 1 (21×21) is the minimum for short payloads.
      expect(matrix.moduleCount, greaterThanOrEqualTo(21));
      expect(matrix.isDark(0, 0), isTrue); // finder pattern is dark
    });

    test('larger payloads produce larger matrices', () {
      final short = encoder.encode('a');
      final long = encoder.encode('civic-commons://pair?v=1&bh=${'a' * 64}&did='
          'f47ac10b-58cc-4372-a567-0e02b2c3d479&sec=${'b' * 43}'
          '&ik=${'c' * 43}&spkid=1&spk=${'d' * 43}&sig=${'e' * 86}');

      expect(long.moduleCount, greaterThanOrEqualTo(short.moduleCount));
    });

    test('matrix has both dark and light modules (non-trivial)', () {
      final matrix = encoder.encode('hello pairing');
      var dark = 0;
      var light = 0;
      for (var y = 0; y < matrix.moduleCount; y++) {
        for (var x = 0; x < matrix.moduleCount; x++) {
          matrix.isDark(y, x) ? dark++ : light++;
        }
      }
      expect(dark, greaterThan(0));
      expect(light, greaterThan(0));
    });

    test('QrMatrix rejects non-square rows', () {
      expect(
        () => QrMatrix.fromRows([
          [true, false],
          [true],
        ]),
        throwsArgumentError,
      );
    });

    test('QrMatrix rejects an empty grid', () {
      expect(() => QrMatrix.fromRows([]), throwsArgumentError);
    });
  });
}
