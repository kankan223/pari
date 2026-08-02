import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/database/data/argon2id_database_key_service.dart';
import 'package:civic_commons/database/domain/database_key_service.dart';

void main() {
  final crypto = CryptoServiceImpl();
  final service = Argon2idDatabaseKeyService(crypto);

  group('Argon2idDatabaseKeyService - key derivation', () {
    test('derives a 256-bit (32-byte) key from a PIN', () async {
      final key = await service.deriveKey('123456');

      expect(key.rawBytes.length, 32);
      expect(key.sqlCipherKey, hasLength(64)); // 32 bytes → 64 hex chars
    });

    test('uses a fresh random salt per derivation (unique keys)', () async {
      final keyA = await service.deriveKey('123456');
      final keyB = await service.deriveKey('123456');

      // Same PIN, different salt → different keys (per-installation salt).
      expect(keyA.sqlCipherKey, isNot(equals(keyB.sqlCipherKey)));
    });

    test('rederiveKey reproduces the same key for the same PIN and salt',
        () async {
      // deriveKey exposes the salt it used (salts are persisted, not secret).
      final keyA = await service.deriveKey('987654');

      // Re-derive with the SAME stored salt → identical key.
      final keyB = await service.rederiveKey('987654', keyA.salt);

      expect(keyB.sqlCipherKey, equals(keyA.sqlCipherKey));
      expect(keyB.rawBytes, equals(keyA.rawBytes));
      expect(keyB.salt, equals(keyA.salt));
    });

    test('sqlCipherKey round-trips through hex encode/decode', () async {
      final key = await service.deriveKey('135790');

      final decoded = Argon2idDatabaseKeyService.fromSqlCipherKey(
        key.sqlCipherKey,
      );
      final reEncoded = Argon2idDatabaseKeyService.toSqlCipherKey(decoded);

      expect(decoded, equals(key.rawBytes));
      expect(reEncoded, equals(key.sqlCipherKey));
    });

    test('derived salt is 16 bytes (128-bit)', () async {
      final key = await service.deriveKey('246810');
      expect(key.salt.length, 16);
    });
  });

  group('Argon2idDatabaseKeyService - SECURITY', () {
    test('different PINs yield different keys', () async {
      final keyA = await service.deriveKey('111111');
      final keyB = await service.deriveKey('222222');

      expect(keyA.sqlCipherKey, isNot(equals(keyB.sqlCipherKey)));
    });

    test('wipe() zeroes the raw key bytes', () async {
      final key = await service.deriveKey('112233');
      final before = key.rawBytes.toList();

      service.wipe(key);

      expect(before, isNot(equals(key.rawBytes.toList())));
      expect(key.rawBytes.every((b) => b == 0), isTrue);
    });
  });
}
