import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../domain/app_database.dart';
import '../domain/migration.dart';

/// SQLCipher-backed [AppDatabase] (data layer — production implementation).
///
/// Uses the `sqflite_sqlcipher` plugin, which encrypts the ENTIRE database
/// file page-by-page with SQLCipher under the key passed to `openDatabase`.
/// A wrong key causes SQLCipher's page HMAC authentication to fail, which the
/// plugin surfaces as an open error — mapped here to
/// [WrongDatabaseKeyException].
///
/// SECURITY CHECKPOINT (Task 3.1): because SQLCipher encrypts the whole file
/// at rest, every column — including `ciphertext`, `participant_hash`,
/// `encrypted_session_state`, `payload` — is stored encrypted on disk. No
/// plaintext sensitive value can exist in the database file.
///
/// NOTE: requires the native SQLCipher library (Android/iOS/macOS). Unit
/// tests exercise the domain logic (schema, migrations, key verification)
/// with real cryptography instead of the platform plugin.
class SqfliteCipherDatabase implements AppDatabase {
  static const String _markerTable = '_vault_key_marker';
  static const String _markerColumn = 'sealed_marker';

  sqlcipher.Database? _db;
  bool _open = false;

  /// The persisted hex-encoded verification marker (empty when unset).
  String _sealedMarker = '';

  @override
  bool get isOpen => _open;

  @override
  Future<void> open({
    required String path,
    required Uint8List key,
    bool runMigrations = true,
  }) async {
    try {
      // SQLCipher encrypts the whole file at rest; a wrong key fails here.
      final db = await sqlcipher.openDatabase(
        path,
        password: _hexKey(key),
      );
      _db = db;
      _open = true;
    } catch (e) {
      final message = e.toString();
      if (_looksLikeWrongKey(message)) {
        throw const WrongDatabaseKeyException(
          'Provided key could not decrypt the database',
        );
      }
      throw DatabaseOpenException('Failed to open database: $e');
    }

    // Marker-table setup is best-effort (a fresh database simply has no
    // marker yet). Migration failures are NOT swallowed — they propagate so
    // callers cannot silently run against a partially-migrated schema.
    try {
      await _ensureMarkerTable();
      await _loadMarker();
    } catch (_) {
      // Marker bookkeeping must never prevent the database from opening.
    }

    if (runMigrations) {
      await MigrationRunner(_SqliteMigrationExecutor(_db!)).migrate();
    }
  }

  @override
  Future<void> close() async {
    await _db?.close();
    _db = null;
    _open = false;
  }

  @override
  Future<int> schemaVersion() async {
    final db = _requireOpen();
    final rows = await db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first.values.first as int;
  }

  /// Stores a sealed verification marker (called after first open with the
  /// correct key).
  Future<void> storeMarker(Uint8List sealed) async {
    final db = _requireOpen();
    final hexMarker = _hex(sealed);
    await db.insert(
      _markerTable,
      {_markerColumn: hexMarker},
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
    );
    _sealedMarker = hexMarker;
  }

  /// The currently persisted sealed marker (hex), or empty if none.
  String get storedMarker => _sealedMarker;

  // -------------------------------------------------------------------------
  // Internals
  // -------------------------------------------------------------------------

  sqlcipher.Database _requireOpen() {
    final db = _db;
    if (db == null || !_open) {
      throw StateError('Database is not open');
    }
    return db;
  }

  Future<void> _ensureMarkerTable() async {
    final db = _requireOpen();
    await db.execute(
      'CREATE TABLE IF NOT EXISTS $_markerTable '
      '($_markerColumn TEXT NOT NULL)',
    );
  }

  Future<void> _loadMarker() async {
    final db = _requireOpen();
    final rows = await db.query(_markerTable, limit: 1);
    _sealedMarker =
        rows.isEmpty ? '' : (rows.first[_markerColumn] as String? ?? '');
  }

  static String _hexKey(Uint8List key) => _hex(key);

  static String _hex(Uint8List bytes) {
    const digits = '0123456789abcdef';
    final out = StringBuffer();
    for (final b in bytes) {
      out.write(digits[(b >> 4) & 0xf]);
      out.write(digits[b & 0xf]);
    }
    return out.toString();
  }

  static bool _looksLikeWrongKey(String message) {
    final lower = message.toLowerCase();
    return lower.contains('file is not a database') ||
        lower.contains('not a database') ||
        lower.contains('wrong key') ||
        lower.contains('decrypt') ||
        lower.contains('password');
  }
}

/// Adapts the SQLCipher database to the domain [MigrationExecutor] port.
class _SqliteMigrationExecutor implements MigrationExecutor {
  final sqlcipher.Database _db;

  const _SqliteMigrationExecutor(this._db);

  @override
  Future<void> execute(String sql) => _db.execute(sql);

  @override
  Future<int> getUserVersion() async {
    final rows = await _db.rawQuery('PRAGMA user_version');
    if (rows.isEmpty) {
      return 0;
    }
    return rows.first.values.first as int;
  }

  @override
  Future<void> setUserVersion(int version) =>
      _db.execute('PRAGMA user_version = $version');
}
