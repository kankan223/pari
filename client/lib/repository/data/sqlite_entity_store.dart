import 'dart:typed_data';

import 'package:sqflite_sqlcipher/sqflite.dart' as sqlcipher;

import '../../ledger/domain/ledger_category.dart';
import '../../ledger/domain/ledger_draft_record.dart';
import '../../ledger/domain/ledger_vote.dart';
import '../../ledger/domain/ledger_vote_record.dart';
import '../../ledger/domain/peer_review.dart';
import '../../pairing/domain/linked_device.dart';
import '../../war_room/domain/evidence_item.dart';
import '../../war_room/data/encrypted_intake_draft_store.dart';
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

/// Row codec for the `ledger_drafts` table (Task 7.4).
///
/// `pin_code` is the coarse civic scope (sensitive column); category is the
/// wire name; headline/body are public civic content. created_at is epoch
/// microseconds so draft ordering survives restarts.
Map<String, Object?> ledgerDraftRecordToRow(LedgerDraftRecord d) => {
      'id': d.id,
      'category': d.category.wireName,
      'pin_code': d.pinCode,
      'headline': d.headline,
      'body': d.body,
      'created_at': d.createdAt.microsecondsSinceEpoch,
    };

LedgerDraftRecord ledgerDraftRecordFromRow(Map<String, Object?> row) =>
    LedgerDraftRecord(
      id: row['id']! as String,
      category: LedgerCategory.fromWireName(row['category']! as String),
      pinCode: row['pin_code']! as String,
      headline: row['headline']! as String,
      body: row['body']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(row['created_at']! as int),
    );

/// Row codec for the `post_votes` table (Task 7.5).
///
/// `direction` is the vote wire name ('up'/'down'/'none'); `updated_at` is
/// epoch microseconds. No identity column exists by design — the row is a
/// per-device aggregate preference inside the encrypted database.
Map<String, Object?> ledgerVoteRecordToRow(LedgerVoteRecord v) => {
      'post_id': v.postId,
      'direction': v.direction.wireName,
      'updated_at': v.updatedAt.microsecondsSinceEpoch,
    };

LedgerVoteRecord ledgerVoteRecordFromRow(Map<String, Object?> row) =>
    LedgerVoteRecord(
      postId: row['post_id']! as String,
      direction: LedgerVoteDirection.fromWireName(row['direction']! as String),
      updatedAt: DateTime.fromMicrosecondsSinceEpoch(row['updated_at']! as int),
    );

/// Row codec for the `peer_reviews` table (Task 7.6).
///
/// `decision` is the review wire name ('approved'/'rejected'/'flagged');
/// `reviewed_at` is epoch microseconds. No identity column exists by design
/// — the row is a per-device review action inside the encrypted database.
Map<String, Object?> peerReviewRecordToRow(PeerReviewRecord r) => {
      'post_id': r.postId,
      'decision': r.decision.wireName,
      'reviewed_at': r.reviewedAt.microsecondsSinceEpoch,
    };

PeerReviewRecord peerReviewRecordFromRow(Map<String, Object?> row) =>
    PeerReviewRecord(
      postId: row['post_id']! as String,
      decision: PeerReviewDecision.fromWireName(row['decision']! as String),
      reviewedAt:
          DateTime.fromMicrosecondsSinceEpoch(row['reviewed_at']! as int),
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

/// Row codec for the `evidence` table (Task 8.2 Encrypted Evidence).
///
/// `sealed_file`/`dek_envelope` are opaque ciphertext BLOBs (SQLite returns
/// BLOB as Uint8List); `created_at` is epoch microseconds. NO filename, NO
/// path, NO identity column exists by design — a filename that embeds
/// sensitive context can never touch the database (SECURITY CHECKPOINT 8.2).
Map<String, Object?> evidenceRecordToRow(EvidenceRecord e) => {
      'id': e.id,
      'case_number': e.caseNumber,
      'sealed_file': e.sealedFile,
      'dek_envelope': e.dekEnvelope,
      'size_bytes': e.sizeBytes,
      'mime_type': e.mimeType,
      'created_at': e.createdAt.microsecondsSinceEpoch,
    };

EvidenceRecord evidenceRecordFromRow(Map<String, Object?> row) =>
    EvidenceRecord(
      id: row['id']! as String,
      caseNumber: row['case_number']! as String,
      sealedFile: row['sealed_file']! as Uint8List,
      dekEnvelope: row['dek_envelope']! as Uint8List,
      sizeBytes: row['size_bytes']! as int,
      mimeType: row['mime_type']! as String,
      createdAt: DateTime.fromMicrosecondsSinceEpoch(
        row['created_at']! as int,
        isUtc: true,
      ),
    );

/// Row codec for the `intake_drafts` table (Task 8.7 Pause, Save & Resume).
///
/// `sealed_payload` is the AES-256-GCM SEALED draft envelope (opaque BLOB —
/// the plaintext narrative never touches the database); `saved_at` is epoch
/// microseconds. ZERO identity columns — the same zero-identity intake
/// contract as the case itself (SECURITY CHECKPOINT 8.7).
Map<String, Object?> intakeDraftRecordToRow(IntakeDraftRecord d) => {
      'id': d.id,
      'sealed_payload': d.sealedPayload,
      'saved_at': d.savedAt.microsecondsSinceEpoch,
    };

IntakeDraftRecord intakeDraftRecordFromRow(Map<String, Object?> row) =>
    IntakeDraftRecord(
      id: row['id']! as String,
      sealedPayload: row['sealed_payload']! as Uint8List,
      savedAt: DateTime.fromMicrosecondsSinceEpoch(
        row['saved_at']! as int,
        isUtc: true,
      ),
    );

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
