import 'dart:convert';
import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart';
import 'double_ratchet_service.dart';

/// Session state storage in SQLCipher database
///
/// Stores Double Ratchet session states securely in an encrypted database
class SessionStorage {
  final String _databasePath;
  final Uint8List _encryptionKey;

  Database? _database;

  SessionStorage({
    required String databasePath,
    required Uint8List encryptionKey,
  })  : _databasePath = databasePath,
        _encryptionKey = encryptionKey;

  /// Initialize the database
  ///
  /// Security: Database is encrypted with the provided key
  Future<void> initialize() async {
    final path = join(_databasePath, 'signal_sessions.db');

    _database = await openDatabase(
      path,
      // SQLCipher requires a String password; encode the derived 256-bit key.
      password: base64Encode(_encryptionKey),
      version: 1,
      onCreate: _onCreate,
    );
  }

  /// Create database schema
  Future<void> _onCreate(Database db, int version) async {
    // Create sessions table
    await db.execute('''
      CREATE TABLE sessions (
        id TEXT PRIMARY KEY,
        remote_identity_key TEXT NOT NULL,
        root_key TEXT NOT NULL,
        send_chain_key TEXT NOT NULL,
        receive_chain_key TEXT NOT NULL,
        send_message_number INTEGER NOT NULL,
        receive_message_number INTEGER NOT NULL,
        previous_chain_length INTEGER NOT NULL,
        dh_key_pair TEXT NOT NULL,
        remote_dh_public_key TEXT,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )
    ''');

    // Create index on remote identity key for faster lookups
    await db.execute('''
      CREATE INDEX idx_remote_identity_key ON sessions(remote_identity_key)
    ''');
  }

  /// Store a session state
  ///
  /// Parameters:
  /// - sessionId: Unique identifier for the session
  /// - remoteIdentityKey: The remote user's identity public key
  /// - ratchetService: The Double Ratchet service instance
  ///
  /// Security: All data is encrypted at rest in SQLCipher
  Future<void> storeSession(
    String sessionId,
    Uint8List remoteIdentityKey,
    DoubleRatchetService ratchetService,
  ) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    final sessionState = ratchetService.getSessionState();
    final now = DateTime.now().millisecondsSinceEpoch;

    // Serialize sensitive data (in production, this would be encrypted)
    const rootKey = 'encrypted_placeholder'; // Placeholder for encrypted data
    const sendChainKey = 'encrypted_placeholder';
    const receiveChainKey = 'encrypted_placeholder';
    const dhKeyPair = 'encrypted_placeholder';
    const remoteDhPublicKey = 'encrypted_placeholder';

    await _database!.insert(
      'sessions',
      {
        'id': sessionId,
        'remote_identity_key': _base64Encode(remoteIdentityKey),
        'root_key': rootKey,
        'send_chain_key': sendChainKey,
        'receive_chain_key': receiveChainKey,
        'send_message_number': sessionState['sendMessageNumber'],
        'receive_message_number': sessionState['receiveMessageNumber'],
        'previous_chain_length': sessionState['previousChainLength'],
        'dh_key_pair': dhKeyPair,
        'remote_dh_public_key': remoteDhPublicKey,
        'created_at': now,
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Retrieve a session state
  ///
  /// Parameters:
  /// - sessionId: Unique identifier for the session
  ///
  /// Returns: The session state, or null if not found
  ///
  /// Security: Data is decrypted when retrieved from SQLCipher
  Future<Map<String, dynamic>?> getSession(String sessionId) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    final result = await _database!.query(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );

    if (result.isEmpty) {
      return null;
    }

    final row = result.first;
    return {
      'sessionId': row['id'] as String,
      'remoteIdentityKey': _base64Decode(row['remote_identity_key'] as String),
      'sendMessageNumber': row['send_message_number'] as int,
      'receiveMessageNumber': row['receive_message_number'] as int,
      'previousChainLength': row['previous_chain_length'] as int,
      'createdAt': row['created_at'] as int,
      'updatedAt': row['updated_at'] as int,
    };
  }

  /// Retrieve a session by remote identity key
  ///
  /// Parameters:
  /// - remoteIdentityKey: The remote user's identity public key
  ///
  /// Returns: The session state, or null if not found
  Future<Map<String, dynamic>?> getSessionByRemoteIdentityKey(
    Uint8List remoteIdentityKey,
  ) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    final result = await _database!.query(
      'sessions',
      where: 'remote_identity_key = ?',
      whereArgs: [_base64Encode(remoteIdentityKey)],
    );

    if (result.isEmpty) {
      return null;
    }

    final row = result.first;
    return {
      'sessionId': row['id'] as String,
      'remoteIdentityKey': _base64Decode(row['remote_identity_key'] as String),
      'sendMessageNumber': row['send_message_number'] as int,
      'receiveMessageNumber': row['receive_message_number'] as int,
      'previousChainLength': row['previous_chain_length'] as int,
      'createdAt': row['created_at'] as int,
      'updatedAt': row['updated_at'] as int,
    };
  }

  /// Update a session state
  ///
  /// Parameters:
  /// - sessionId: Unique identifier for the session
  /// - ratchetService: The Double Ratchet service instance
  ///
  /// Security: All data is encrypted at rest in SQLCipher
  Future<void> updateSession(
    String sessionId,
    DoubleRatchetService ratchetService,
  ) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    final sessionState = ratchetService.getSessionState();
    final now = DateTime.now().millisecondsSinceEpoch;

    await _database!.update(
      'sessions',
      {
        'send_message_number': sessionState['sendMessageNumber'],
        'receive_message_number': sessionState['receiveMessageNumber'],
        'previous_chain_length': sessionState['previousChainLength'],
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Delete a session
  ///
  /// Parameters:
  /// - sessionId: Unique identifier for the session
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteSession(String sessionId) async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    await _database!.delete(
      'sessions',
      where: 'id = ?',
      whereArgs: [sessionId],
    );
  }

  /// Delete all sessions (for account deletion or duress PIN)
  ///
  /// Security: This is a destructive operation that cannot be undone
  Future<void> deleteAllSessions() async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    await _database!.delete('sessions');
  }

  /// Get all sessions
  ///
  /// Returns: List of all session states
  Future<List<Map<String, dynamic>>> getAllSessions() async {
    if (_database == null) {
      throw StateError('Database not initialized');
    }

    final result = await _database!.query('sessions');
    return result.map((row) {
      return {
        'sessionId': row['id'] as String,
        'remoteIdentityKey':
            _base64Decode(row['remote_identity_key'] as String),
        'sendMessageNumber': row['send_message_number'] as int,
        'receiveMessageNumber': row['receive_message_number'] as int,
        'previousChainLength': row['previous_chain_length'] as int,
        'createdAt': row['created_at'] as int,
        'updatedAt': row['updated_at'] as int,
      };
    }).toList();
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null) {
      await _database!.close();
      _database = null;
    }
  }

  /// Base64 encode helper
  String _base64Encode(Uint8List data) {
    return base64Encode(data);
  }

  /// Base64 decode helper
  Uint8List _base64Decode(String data) {
    return Uint8List.fromList(base64Decode(data));
  }
}
