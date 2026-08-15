import 'dart:typed_data';

/// Port (domain boundary) for the encrypted offline-first database.
///
/// The concrete implementation (SQLCipher-backed in production) lives in the
/// data layer and is injected at composition time. The domain depends only on
/// this abstract interface, keeping repositories decoupled from SQLite.
///
/// Security contract:
/// - The database file is encrypted at rest with SQLCipher under the
///   Argon2id-derived key — a wrong key fails to open (see
///   [WrongDatabaseKeyException]).
/// - Sensitive columns (ciphertext, participant hashes, payloads) are never
///   stored in plaintext: the whole file is encrypted page-level by
///   SQLCipher, and those columns hold only ciphertext/opaque blobs.
abstract class AppDatabase {
  /// Opens (creating if necessary) the encrypted database at [path].
  ///
  /// Parameters:
  /// - path: on-disk location of the SQLCipher database file
  /// - key: the Argon2id-derived 256-bit key
  /// - runMigrations: when true, applies pending schema migrations after a
  ///   successful open
  ///
  /// Throws:
  /// - [WrongDatabaseKeyException] if [key] cannot unlock the database
  /// - [DatabaseOpenException] for other open failures
  Future<void> open({
    required String path,
    required Uint8List key,
    bool runMigrations = true,
  });

  /// Returns true when a database has been opened and is ready.
  bool get isOpen;

  /// Closes the database and releases resources.
  Future<void> close();

  /// Reads the current schema version (0 for a fresh database).
  Future<int> schemaVersion();
}

/// Thrown when the provided key cannot decrypt the SQLCipher database.
///
/// This is the "wrong key" failure path: SQLCipher's page-level HMAC
/// authentication rejects an incorrect key. The same exception is thrown
/// regardless of *how* wrong the key is — no information about the key is
/// ever exposed.
class WrongDatabaseKeyException implements Exception {
  final String message;

  const WrongDatabaseKeyException(this.message);

  @override
  String toString() => 'WrongDatabaseKeyException: $message';
}

/// Thrown when the database cannot be opened for reasons other than a wrong
/// key (corrupt file, I/O error, etc.).
class DatabaseOpenException implements Exception {
  final String message;

  const DatabaseOpenException(this.message);

  @override
  String toString() => 'DatabaseOpenException: $message';
}
