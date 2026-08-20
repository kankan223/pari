import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CryptoServiceImpl - Task 13.1', () {
    late CryptoServiceImpl crypto;

    setUp(() {
      crypto = CryptoServiceImpl();
    });

    group('deriveKeyFromPin', () {
      test('derives a 32-byte key from valid PIN and salt', () async {
        final salt = crypto.generateSalt();
        final key = await crypto.deriveKeyFromPin('123456', salt);
        expect(key.length, 32);
      });

      test('throws on empty PIN', () async {
        final salt = crypto.generateSalt();
        expect(
          () => crypto.deriveKeyFromPin('', salt),
          throwsArgumentError,
        );
      });

      test('throws on wrong salt length', () async {
        final wrongSalt = Uint8List(8); // Wrong length
        expect(
          () => crypto.deriveKeyFromPin('123456', wrongSalt),
          throwsArgumentError,
        );
      });

      test('same PIN and salt produce same key (deterministic)', () async {
        final salt = crypto.generateSalt();
        final key1 = await crypto.deriveKeyFromPin('123456', salt);
        final key2 = await crypto.deriveKeyFromPin('123456', salt);
        expect(key1, equals(key2));
      });

      test('different PINs produce different keys', () async {
        final salt = crypto.generateSalt();
        final key1 = await crypto.deriveKeyFromPin('123456', salt);
        final key2 = await crypto.deriveKeyFromPin('654321', salt);
        expect(key1, isNot(equals(key2)));
      });

      test('different salts produce different keys', () async {
        final salt1 = crypto.generateSalt();
        final salt2 = crypto.generateSalt();
        final key1 = await crypto.deriveKeyFromPin('123456', salt1);
        final key2 = await crypto.deriveKeyFromPin('123456', salt2);
        expect(key1, isNot(equals(key2)));
      });
    });

    group('encrypt/decrypt', () {
      test('encrypts and decrypts data round-trip', () async {
        final salt = crypto.generateSalt();
        final key = await crypto.deriveKeyFromPin('123456', salt);
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final ciphertext = await crypto.encrypt(plaintext, key);
        expect(ciphertext, isNot(equals(plaintext)));
        expect(ciphertext.length, greaterThan(plaintext.length));

        final decrypted = await crypto.decrypt(ciphertext, key);
        expect(decrypted, equals(plaintext));
      });

      test('encryption produces different ciphertext each time (random nonce)', () async {
        final salt = crypto.generateSalt();
        final key = await crypto.deriveKeyFromPin('123456', salt);
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final ciphertext1 = await crypto.encrypt(plaintext, key);
        final ciphertext2 = await crypto.encrypt(plaintext, key);
        expect(ciphertext1, isNot(equals(ciphertext2)));
      });

      test('decryption with wrong key fails', () async {
        final salt = crypto.generateSalt();
        final key1 = await crypto.deriveKeyFromPin('123456', salt);
        final key2 = await crypto.deriveKeyFromPin('654321', salt);
        final plaintext = Uint8List.fromList([1, 2, 3, 4, 5]);

        final ciphertext = await crypto.encrypt(plaintext, key1);
        expect(
          () => crypto.decrypt(ciphertext, key2),
          throwsA(anything),
        );
      });
    });

    group('generateEd25519KeyPair', () {
      test('generates a valid key pair', () async {
        final keyPair = await crypto.generateEd25519KeyPair();
        expect(keyPair, isNotNull);
        final publicKey = await keyPair.extractPublicKey();
        expect(publicKey, isNotNull);
      });
    });

    group('generateCurve25519KeyPair', () {
      test('generates a valid key pair', () async {
        final keyPair = await crypto.generateCurve25519KeyPair();
        expect(keyPair, isNotNull);
        final publicKey = await keyPair.extractPublicKey();
        expect(publicKey, isNotNull);
      });
    });

    group('generateSalt', () {
      test('generates a 16-byte salt', () {
        final salt = crypto.generateSalt();
        expect(salt.length, 16);
      });

      test('generates different salts each time', () {
        final salt1 = crypto.generateSalt();
        final salt2 = crypto.generateSalt();
        expect(salt1, isNot(equals(salt2)));
      });
    });

    group('secureWipe', () {
      test('overwrites data with zeros', () {
        final data = Uint8List.fromList([1, 2, 3, 4, 5]);
        crypto.secureWipe(data);
        expect(data, equals(Uint8List(5)));
      });

      test('handles empty data', () {
        final data = Uint8List(0);
        crypto.secureWipe(data);
        expect(data, isEmpty);
      });
    });
  });
}
