import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../../pairing/domain/linked_device.dart';
import '../domain/conversation.dart';
import '../domain/connection_request.dart';
import '../domain/entity_store.dart';
import '../domain/message.dart';
import '../domain/sync_queue_item.dart';

/// SQLCipher-backed [EntityStore] (data layer — production implementation).
///
/// Wraps a table of the encrypted SQLCipher database. Every row is written
/// to the ciphertext-encrypted file at rest — sensitive columns (ciphertext,
/// participant hashes, session state, queue payloads) never exist in
/// plaintext on disk.
///
/// SECURITY CHECKPOINT (Task 3.2): this store performs NO network I/O and
/// never serializes raw plaintext — repositories feed it opaque ciphertext /
/// hash values only.
///
/// NOTE: requires the native SQLCipher library (Android/iOS/macOS). Unit
/// tests exercise the repository logic with in-memory fakes instead.
class SqliteEntityStore<T> implements EntityStore<T> {
  final sqlcipher.Database _db;
  final String _table;
  final String _idColumn;
  final Map<String, Object?> Function(T) _toRow;
  final T Function(Map<String, Object?>) _fromRow;

  SqliteEntityStore({
    required sqlcipher.Database db,
    required String table,
    required String idColumn,
    required Map<String, Object?> Function(T) toRow,
    required T Function(Map<String, Object?>) fromRow,
  })  : _db = db,
        _table = table,
        _idColumn = idColumn,
        _toRow = toRow,
        _fromRow = fromRow;

  @override
  Future<void> insert(T entity) async {
    await _db.insert(
      _table,
      _toRow(entity),
      conflictAlgorithm: sqlcipher.ConflictAlgorithm.replace,
    );
  }

  @override
  Future<void> update(T entity) async {
    final row = _toRow(entity);
    final id = row[_idColumn];
    await _db.update(_table, row, where: '$_idColumn = ?', whereArgs: [id]);
  }

  @override
  Future<void> delete(String id) async {
    await _db.delete(_table, where: '$_idColumn = ?', whereArgs: [id]);
  }

  @override
  Future<T?> getById(String id) async {
    final rows = await _db.query(
      _table,
      where: '$_idColumn = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : _fromRow(rows.first);
  }

  @override
  Future<List<T>> getAll() async {
    final rows = await _db.query(_table);
    return rows.map(_fromRow).toList(growable: false);
  }
}

// ---------------------------------------------------------------------------
// Row codecs (entity <-> SQLCipher row) — SQLite stores BLOB as Uint8List.
// ---------------------------------------------------------------------------

/// Row codec for the `conversations` table.
Map<String, Object?> conversationToRow(Conversation c) => {
      'id': c.id,
      'participant_hash': c.participantHash,
      'encrypted_session_state': c.encryptedSessionState,
    };

Conversation conversationFromRow(Map<String, Object?> row) => Conversation(
      id: row['id']! as String,
      participantHash: row['participant_hash']! as String,
      encryptedSessionState: row['encrypted_session_state']! as Uint8List,
    );

/// Row codec for the `messages` table.
Map<String, Object?> messageToRow(Message m) => {
      'id': m.id,
      'conversation_id': m.conversationId,
      'ciphertext': m.ciphertext,
      'direction': m.direction.wireName,
      'delivered': m.delivered ? 1 : 0,
      'expires_at': m.expiresAt?.millisecondsSinceEpoch,
    };

Message messageFromRow(Map<String, Object?> row) => Message(
      id: row['id']! as String,
      conversationId: row['conversation_id']! as String,
      ciphertext: row['ciphertext']! as Uint8List,
      direction: MessageDirection.fromWireName(row['direction'] as String?),
      delivered: (row['delivered']! as int) == 1,
      expiresAt: row['expires_at'] == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(row['expires_at']! as int),
    );

/// Row codec for the `connection_requests` table (Task 6.2).
///
/// requester_hash / recipient_hash are blind hashes (sensitive columns —
/// opaque values only, never phones/usernames); status is the relay wire
/// name so a future sync transport can map it directly.
Map<String, Object?> connectionRequestToRow(ConnectionRequest r) => {
      'id': r.id,
      'requester_hash': r.requesterHash,
      'recipient_hash': r.recipientHash,
      'status': r.status.wireName,
    };

ConnectionRequest connectionRequestFromRow(Map<String, Object?> row) =>
    ConnectionRequest(
      id: row['id']! as String,
      requesterHash: row['requester_hash']! as String,
      recipientHash: row['recipient_hash']! as String,
      status: ConnectionRequestStatus.fromWireName(row['status']! as String),
    );

/// Row codec for the `devices` table (Task 6.5 multi-device pairing).
///
/// blind_hash is the owner's 64-hex blind hash (sensitive column);
/// public_key is the linked device's opaque public key bytes (base64url
/// material — never a private key); revoked is 0/1.
Map<String, Object?> linkedDeviceToRow(LinkedDevice d) => {
      'id': d.deviceId,
      'blind_hash': d.ownerBlindHash,
      'public_key': d.publicKey,
      'paired_at': d.pairedAt.millisecondsSinceEpoch,
      'revoked': d.revoked ? 1 : 0,
    };

LinkedDevice linkedDeviceFromRow(Map<String, Object?> row) => LinkedDevice(
      deviceId: row['id']! as String,
      ownerBlindHash: row['blind_hash']! as String,
      publicKey: row['public_key']! as Uint8List,
      pairedAt: DateTime.fromMillisecondsSinceEpoch(row['paired_at']! as int),
      revoked: (row['revoked']! as int) == 1,
    );

const _operationToDb = {
  SyncOperationType.create: 'POST',
  SyncOperationType.update: 'PUT',
  SyncOperationType.delete: 'DELETE',
};

const _statusToDb = {
  SyncQueueStatus.pending: 'pending',
  SyncQueueStatus.inProgress: 'in_progress',
  SyncQueueStatus.success: 'success',
  SyncQueueStatus.failed: 'failed',
};

/// Row codec for the `sync_queue` table (status/operation stored as TEXT;
/// created_at + last_attempt_at stored as epoch microseconds so ordering and
/// retry gating survive restarts).
Map<String, Object?> syncQueueItemToRow(SyncQueueItem i) => {
      'id': i.id,
      'operation_type': _operationToDb[i.operationType],
      'payload': i.payload,
      'status': _statusToDb[i.status],
      'retry_count': i.retryCount,
      'created_at': i.createdAt.microsecondsSinceEpoch,
      'last_attempt_at': i.lastAttemptAt?.microsecondsSinceEpoch,
    };

SyncQueueItem syncQueueItemFromRow(Map<String, Object?> row) => SyncQueueItem(
      id: row['id']! as String,
      operationType: _operationFromDb(row['operation_type']! as String),
      payload: row['payload']! as Uint8List,
      status: _statusFromDb(row['status']! as String),
      retryCount: row['retry_count']! as int,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int),
      lastAttemptAt: row['last_attempt_at'] == null
          ? null
          : DateTime.fromMicrosecondsSinceEpoch(row['last_attempt_at']! as int),
    );

SyncOperationType _operationFromDb(String value) => switch (value) {
      'POST' => SyncOperationType.create,
      'PUT' => SyncOperationType.update,
      'DELETE' => SyncOperationType.delete,
      _ => throw ArgumentError('Unknown operation_type: $value'),
    };

SyncQueueStatus _statusFromDb(String value) => switch (value) {
      'pending' => SyncQueueStatus.pending,
      'in_progress' => SyncQueueStatus.inProgress,
      'success' => SyncQueueStatus.success,
      'failed' => SyncQueueStatus.failed,
      _ => throw ArgumentError('Unknown status: $value'),
    };
