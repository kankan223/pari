import 'dart:typed_data';

/// A SQLCipher database key derived from the user's PIN.
///
/// SQLCipher accepts a raw byte key or a passphrase; a raw key of 32 bytes
/// (256 bits) is the strongest option. [rawBytes] is the Argon2id-derived
/// 256-bit key material; [sqlCipherKey] is the string form used by the
/// sqflite_sqlcipher `password` parameter.
///
/// [salt] is the random 16-byte salt used for this derivation. Salts are NOT
/// secret — the app persists the salt alongside the database so the key can
/// be re-derived from the PIN at unlock ([DatabaseKeyService.rederiveKey]).
class DatabaseKey {
  final Uint8List rawBytes;

  /// hex-encoded form passed to SQLCipher's password parameter.
  final String sqlCipherKey;

  /// The 16-byte salt used for this derivation (persisted, not secret).
  final Uint8List salt;

  const DatabaseKey({
    required this.rawBytes,
    required this.sqlCipherKey,
    required this.salt,
  });
}

/// Port (domain use case) for deriving the SQLCipher database key from the
/// user's PIN.
///
/// Security contract:
/// - The key is derived with Argon2id (memory-hard, GPU-resistant) via the
///   existing `CryptoService.deriveKeyFromPin`.
/// - A unique random salt is used, so the same PIN on two devices yields
///   different keys, and the key cannot be precomputed (rainbow tables).
/// - The returned [DatabaseKey] must be wiped from memory when no longer
///   needed, and must NEVER be logged, persisted, or transmitted.
abstract class DatabaseKeyService {
  /// Derives a fresh SQLCipher key from [pin] using a new random salt.
  ///
  /// The returned [DatabaseKey] includes the salt that produced it so the
  /// caller can persist it (salts are public) for later re-derivation.
  Future<DatabaseKey> deriveKey(String pin);

  /// Re-derives the key from [pin] and the stored [salt] (used when opening
  /// an existing database whose salt is already known).
  Future<DatabaseKey> rederiveKey(String pin, Uint8List salt);
}
