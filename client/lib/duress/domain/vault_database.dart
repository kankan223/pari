import 'dart:typed_data';

/// A single encrypted record stored inside a vault database.
///
/// Records are identified by a string key and carry an opaque payload
/// (ciphertext from the caller's perspective — the database encrypts the
/// entire content body at rest).
class VaultRecord {
  /// Stable identifier for the record.
  final String id;

  /// Opaque payload bytes.
  final Uint8List payload;

  const VaultRecord({
    required this.id,
    required this.payload,
  });
}

/// Port (domain boundary) for an encrypted on-device vault database.
///
/// The domain layer depends on this abstract interface; the data layer
/// provides a concrete implementation (e.g. a file-backed encrypted store,
/// or SQLCipher in production).
///
/// Security contract:
/// - The database file itself is always encrypted with the vault key.
/// - A database has no notion of "real" vs "duress" — it is just a database.
///   Which PIN opens which database is determined purely by decryption
///   success at unlock time, never by a stored flag.
/// - No method here accepts or persists any real/duress indicator.
abstract class VaultDatabase {
  /// Stable identifier / filename of the database (e.g. `vault.db`).
  String get name;

  /// Returns true if the database file exists and has a valid header.
  Future<bool> isInitialized();

  /// Initializes a new encrypted database.
  ///
  /// Parameters:
  /// - key: the 32-byte AES-256 key derived (Argon2id) from this vault's PIN
  /// - salt: the 16-byte Argon2id salt for this vault's key derivation path
  /// - seedRecords: optional records written during initialization (e.g.
  ///   plausible decoy content so the decoy database is a valid-looking DB)
  ///
  /// Throws a [StateError] if the database is already initialized.
  Future<void> initialize({
    required Uint8List key,
    required Uint8List salt,
    List<VaultRecord> seedRecords = const [],
  });

  /// Reads the 16-byte salt stored in this vault's header.
  ///
  /// Salts are public (Argon2id salts need not be secret); they are needed
  /// at unlock time to re-derive the database key from the entered PIN.
  Future<Uint8List> readSalt();

  /// Returns true only if [key] successfully decrypts this vault's content.
  ///
  /// Never throws on a wrong key — a wrong key simply returns false. This is
  /// the primitive that powers "which PIN successfully decrypts which DB".
  Future<bool> tryOpen(Uint8List key);

  /// Writes (or replaces) a record, re-encrypting the content body under [key].
  ///
  /// Throws if [key] cannot decrypt this vault.
  Future<void> writeRecord(Uint8List key, VaultRecord record);

  /// Returns all records currently stored in the vault.
  ///
  /// Throws if [key] cannot decrypt this vault.
  Future<List<VaultRecord>> readRecords(Uint8List key);

  /// Overwrites the file with zeros and deletes it (secure destruction).
  Future<void> deleteAll();

  /// Releases any open resources.
  Future<void> close();
}
