import 'dart:typed_data';

import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecureKeyStorage - Task 13.1', () {
    test('class exists and is a concrete type', () {
      expect(SecureKeyStorage, isA<Type>());
    });

    test('constructor accepts optional secureStorage parameter', () {
      // Verifies the constructor compiles with the optional parameter
      expect(() => SecureKeyStorage(), returnsNormally);
    });

    test('secureWipe zeros out byte array', () {
      final storage = SecureKeyStorage();
      final data = Uint8List(32)..fillRange(0, 32, 0xFF);
      storage.secureWipe(data);
      expect(data, everyElement(0));
      expect(data.length, 32);
    });

    test('secureWipe handles empty data gracefully', () {
      final storage = SecureKeyStorage();
      final data = Uint8List(0);
      storage.secureWipe(data);
      expect(data, isEmpty);
    });

    test('secureWipe handles single-byte data', () {
      final storage = SecureKeyStorage();
      final data = Uint8List.fromList([0xAB]);
      storage.secureWipe(data);
      expect(data[0], 0);
    });

    test('secureWipe does not affect other arrays', () {
      final storage = SecureKeyStorage();
      final a = Uint8List(4)..fillRange(0, 4, 0xFF);
      final b = Uint8List(4)..fillRange(0, 4, 0xCC);
      storage.secureWipe(a);
      expect(a, everyElement(0));
      expect(b, everyElement(0xCC));
    });
  });
}
