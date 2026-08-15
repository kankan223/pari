import 'dart:typed_data';

import 'package:convert/convert.dart' show hex;

import '../../crypto/crypto_service.dart';
import '../domain/database_key_service.dart';

/// Argon2id-based [DatabaseKeyService] (data layer).
///
/// Derives the SQLCipher database key from the user's PIN using the existing
/// `CryptoService.deriveKeyFromPin` (Argon2id, memory=64MB, iterations=3,
/// parallelism=4 → 256-bit key).
///
/// Security contract:
/// - A fresh random 16-byte salt is generated per database (via
///   [CryptoService.generateSalt]) so keys are unique per installation.
/// - The PIN bytes and derived key are handled only in memory and wiped when
///   possible; the raw key is never logged or persisted — only the salt is
///   stored (salts are not secret) so the key can be re-derived at unlock.
class Argon2idDatabaseKeyService implements DatabaseKeyService {
  final CryptoService _crypto;

  const Argon2idDatabaseKeyService(this._crypto);

  @override
  Future<DatabaseKey> deriveKey(String pin) async {
    final salt = _crypto.generateSalt();
    return _buildKey(pin, salt);
  }

  @override
  Future<DatabaseKey> rederiveKey(String pin, Uint8List salt) async {
    return _buildKey(pin, salt);
  }

  Future<DatabaseKey> _buildKey(String pin, Uint8List salt) async {
    final raw = await _crypto.deriveKeyFromPin(pin, salt);
    return DatabaseKey(
      rawBytes: raw,
      sqlCipherKey: hex.encode(raw),
      salt: Uint8List.fromList(salt),
    );
  }

  /// Wipes a derived key's raw bytes from memory.
  void wipe(DatabaseKey key) {
    key.rawBytes.fillRange(0, key.rawBytes.length, 0);
  }

  /// Encodes the raw key bytes to hex for SQLCipher's password parameter.
  static String toSqlCipherKey(Uint8List raw) => hex.encode(raw);

  /// Decodes a SQLCipher hex key back to raw bytes.
  static Uint8List fromSqlCipherKey(String hexKey) =>
      Uint8List.fromList(hex.decode(hexKey));
}
