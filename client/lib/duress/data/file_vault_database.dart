import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service.dart';
import 'package:civic_commons/duress/domain/vault_database.dart';

/// File-backed encrypted vault database (data layer implementation).
///
/// On-disk layout (all bytes little-endian):
/// ```
/// [9 bytes]  magic        "CIVIC_DB1"
/// [16 bytes] salt         Argon2id salt for this vault's key derivation path
/// [4 bytes]  bodyLength   length of the encrypted body in bytes
/// [N bytes]  body         AES-256-GCM(ciphertext || mac) of the content body
/// ```
///
/// The content body is the concatenation of every [VaultRecord] (id length,
/// id bytes, payload length, payload bytes). The whole body is encrypted as a
/// single AES-256-GCM blob under the vault key, so:
/// - A wrong key fails GCM authentication → [tryOpen] returns false.
/// - Records are never visible in plaintext on disk.
///
/// Security:
/// - No real/duress indicator of any kind is ever written to the file.
/// - The salt is public (Argon2id salts are not secret) and is stored with
///   the file so the key can be re-derived from the entered PIN at unlock.
/// - [deleteAll] overwrites the file with zeros before deleting it.
class FileVaultDatabase implements VaultDatabase {
  /// Magic header identifying a civic vault database file.
  ///
  /// NOTE: "CIVIC_DB1" is 9 bytes, so the header size must be derived from
  /// `_magic.length` (never hard-coded) to keep every offset consistent.
  static final List<int> _magic = utf8.encode('CIVIC_DB1');

  /// Minimum file size: magic (9) + salt (16) + bodyLength (4) = 29.
  static int get _minFileSize => _magic.length + 16 + 4;

  final File _file;
  final CryptoService _crypto;

  @override
  final String name;

  FileVaultDatabase({
    required this.name,
    required File file,
    required CryptoService cryptoService,
  })  : _file = file,
        _crypto = cryptoService;

  @override
  Future<bool> isInitialized() async {
    if (!await _file.exists()) {
      return false;
    }
    try {
      final bytes = await _file.readAsBytes();
      if (bytes.length < _minFileSize) {
        return false;
      }
      return _startsWithMagic(bytes);
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> initialize({
    required Uint8List key,
    required Uint8List salt,
    List<VaultRecord> seedRecords = const [],
  }) async {
    if (await isInitialized()) {
      throw StateError('Vault database "$name" is already initialized');
    }
    if (key.length != 32) {
      throw ArgumentError('Vault key must be 32 bytes for AES-256');
    }
    if (salt.length != 16) {
      throw ArgumentError('Vault salt must be 16 bytes');
    }

    final body = _serializeRecords(seedRecords);
    final encryptedBody = await _crypto.encrypt(body, key);

    final bytes = BytesBuilder(copy: false)
      ..add(_magic)
      ..add(salt)
      ..add(_uint32(encryptedBody.length))
      ..add(encryptedBody);

    await _file.writeAsBytes(bytes.toBytes(), flush: true);
  }

  @override
  Future<Uint8List> readSalt() async {
    final bytes = await _readValidFile();
    return Uint8List.fromList(bytes.sublist(_magic.length, _magic.length + 16));
  }

  @override
  Future<bool> tryOpen(Uint8List key) async {
    try {
      final encryptedBody = await _readEncryptedBody();
      if (encryptedBody == null) {
        return false;
      }
      // GCM authentication fails for a wrong key, throwing before we ever
      // look at the plaintext — exactly like SQLCipher's key check.
      await _crypto.decrypt(encryptedBody, key);
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> writeRecord(Uint8List key, VaultRecord record) async {
    final records = await readRecords(key);
    records.add(record);
    final bytes = await _readValidFile();

    final body = _serializeRecords(records);
    final encryptedBody = await _crypto.encrypt(body, key);

    // Preserve the header (magic + salt) and swap in the new encrypted body.
    final headerLength = _magic.length + 16;
    final header = bytes.sublist(0, headerLength);
    final out = BytesBuilder(copy: false)
      ..add(header)
      ..add(_uint32(encryptedBody.length))
      ..add(encryptedBody);

    await _file.writeAsBytes(out.toBytes(), flush: true);
  }

  @override
  Future<List<VaultRecord>> readRecords(Uint8List key) async {
    final encryptedBody = await _readEncryptedBody();
    if (encryptedBody == null) {
      throw StateError('Vault database "$name" is not initialized');
    }
    final body = await _crypto.decrypt(encryptedBody, key);
    return _deserializeRecords(body);
  }

  @override
  Future<void> deleteAll() async {
    if (!await _file.exists()) {
      return;
    }
    // Overwrite with zeros before deleting to reduce forensic residue.
    try {
      final length = await _file.length();
      await _file.writeAsBytes(Uint8List(length), flush: true);
    } catch (_) {
      // Best-effort wipe; deletion must still proceed.
    }
    await _file.delete();
  }

  @override
  Future<void> close() async {
    // Nothing to release for the file-backed implementation.
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  Future<Uint8List> _readValidFile() async {
    if (!await _file.exists()) {
      throw StateError('Vault database "$name" does not exist');
    }
    final bytes = await _file.readAsBytes();
    if (bytes.length < _minFileSize || !_startsWithMagic(bytes)) {
      throw StateError('Vault database "$name" is corrupt or not a vault file');
    }
    return bytes;
  }

  /// Returns the encrypted body bytes, or null if the file is not initialized.
  Future<Uint8List?> _readEncryptedBody() async {
    try {
      final bytes = await _readValidFile();
      final bodyLength = _readUint32(bytes, _magic.length + 16);
      if (bytes.length < _minFileSize + bodyLength) {
        return null;
      }
      final start = _minFileSize;
      return Uint8List.fromList(bytes.sublist(start, start + bodyLength));
    } catch (_) {
      return null;
    }
  }

  bool _startsWithMagic(List<int> bytes) {
    for (var i = 0; i < _magic.length; i++) {
      if (bytes[i] != _magic[i]) {
        return false;
      }
    }
    return true;
  }

  /// Serializes records into the plaintext content body.
  Uint8List _serializeRecords(List<VaultRecord> records) {
    final builder = BytesBuilder(copy: false)..add(_uint32(records.length));
    for (final record in records) {
      final idBytes = utf8.encode(record.id);
      builder.add(_uint16(idBytes.length));
      builder.add(idBytes);
      builder.add(_uint32(record.payload.length));
      builder.add(record.payload);
    }
    return builder.toBytes();
  }

  /// Deserializes the plaintext content body into records.
  List<VaultRecord> _deserializeRecords(Uint8List body) {
    var offset = 0;
    final count = _readUint32(body, offset);
    offset += 4;

    final records = <VaultRecord>[];
    for (var i = 0; i < count; i++) {
      final idLength = _readUint16(body, offset);
      offset += 2;
      final id = utf8.decode(body.sublist(offset, offset + idLength));
      offset += idLength;

      final payloadLength = _readUint32(body, offset);
      offset += 4;
      final payload = Uint8List.fromList(
        body.sublist(offset, offset + payloadLength),
      );
      offset += payloadLength;

      records.add(VaultRecord(id: id, payload: payload));
    }
    return records;
  }

  List<int> _uint32(int value) => [
        value & 0xff,
        (value >> 8) & 0xff,
        (value >> 16) & 0xff,
        (value >> 24) & 0xff,
      ];

  List<int> _uint16(int value) => [value & 0xff, (value >> 8) & 0xff];

  int _readUint32(List<int> bytes, int offset) =>
      bytes[offset] |
      (bytes[offset + 1] << 8) |
      (bytes[offset + 2] << 16) |
      (bytes[offset + 3] << 24);

  int _readUint16(List<int> bytes, int offset) =>
      bytes[offset] | (bytes[offset + 1] << 8);
}
