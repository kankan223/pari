/// Backup/restore mechanism for the offline sync queue (Task 5.6).
///
/// A backup is a portable JSON envelope of every queued mutation:
///
/// ```json
/// {
///   "version": 1,
///   "exportedAt": 1785999000000000,
///   "items": [
///     {"id": "…", "operationType": "create", "payload": "<base64>",
///      "status": "pending", "retryCount": 0, "createdAt": 1785999000000000,
///      "lastAttemptAt": null}
///   ]
/// }
/// ```
///
/// SECURITY CHECKPOINT (Task 5.6): the envelope carries ONLY the already
/// sealed payloads (base64 of the AES-256-GCM ciphertext) plus non-PII
/// metadata — UUIDs, operation types, statuses, retry counters, and UTC
/// timestamps. Raw mutation plaintext NEVER appears in a backup. Restore
/// inserts the sealed payloads byte-for-byte; the payload cipher is never
/// invoked on the backup path, so a restore cannot accidentally re-encrypt
/// (double-seal) or decrypt anything.
///
/// The operation/status vocabulary matches the SQLCipher row codec
/// (`sqlite_entity_store.dart`) so a backup can be restored into a fresh
/// encrypted database without translation.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'entity_store.dart';
import 'sync_queue_item.dart';

/// Version of the portable queue backup envelope. Bump (with a migration) if
/// the format ever changes; restore refuses unknown versions.
const int syncQueueBackupVersion = 1;

/// Serializes [items] into the version-1 backup envelope, oldest first.
///
/// [exportedAt] is clock-injectable for deterministic tests.
String serializeQueueBackup(
  List<SyncQueueItem> items, {
  DateTime? exportedAt,
}) {
  final ordered = [...items]
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  return jsonEncode({
    'version': syncQueueBackupVersion,
    'exportedAt': (exportedAt ?? DateTime.now()).microsecondsSinceEpoch,
    'items': ordered.map(_itemToJson).toList(growable: false),
  });
}

/// Deserializes a backup envelope back into queue items.
///
/// Strict bounds: the ENTIRE envelope is validated before any item is
/// returned — unknown versions, unknown operation/status strings, non-base64
/// payloads, or structurally malformed entries throw [FormatException] (so a
/// restore caller never partially applies a corrupt backup).
List<SyncQueueItem> deserializeQueueBackup(String json) {
  final Object? decoded;
  try {
    decoded = jsonDecode(json);
  } on FormatException catch (e) {
    throw FormatException('Queue backup is not valid JSON: $e');
  }
  if (decoded is! Map<String, dynamic>) {
    throw const FormatException('Queue backup must be a JSON object');
  }
  if (decoded['version'] != syncQueueBackupVersion) {
    throw FormatException(
      'Unsupported queue backup version: ${decoded['version']} '
      '(expected $syncQueueBackupVersion)',
    );
  }
  final rawItems = decoded['items'];
  if (rawItems is! List) {
    throw const FormatException('Queue backup "items" must be a list');
  }
  return rawItems.map(_itemFromJson).toList(growable: false);
}

/// Store-bound backup service (Task 5.6).
///
/// Wraps the same [EntityStore] the queue repository uses, so export reads
/// exactly what is persisted and restore writes exactly what a cold start
/// would read back — with no translation layer in between.
class SyncQueueBackup {
  final EntityStore<SyncQueueItem> _store;

  const SyncQueueBackup({required EntityStore<SyncQueueItem> store})
      : _store = store;

  /// Exports every queued item (oldest first) as a portable JSON envelope.
  Future<String> exportQueue({DateTime? exportedAt}) async {
    final all = await _store.getAll();
    return serializeQueueBackup(all, exportedAt: exportedAt);
  }

  /// Restores items from a backup envelope into the store.
  ///
  /// The envelope is fully validated by [deserializeQueueBackup] BEFORE any
  /// insert — a corrupt backup never partially mutates the queue. Sealed
  /// payloads are inserted as-is (never re-encrypted). Items whose id is
  /// already present are SKIPPED, so restoring the same backup twice (or onto
  /// a store that already holds some of its items) is idempotent and can
  /// never duplicate a mutation. Returns the number of items restored.
  Future<int> restoreQueue(String json) async {
    final items = deserializeQueueBackup(json);
    var restored = 0;
    for (final item in items) {
      if (await _store.getById(item.id) != null) {
        continue; // already present — idempotent restore, no duplicates.
      }
      await _store.insert(item);
      restored++;
    }
    return restored;
  }
}

// ---------------------------------------------------------------------------
// Envelope codec
// ---------------------------------------------------------------------------

Map<String, Object?> _itemToJson(SyncQueueItem item) => {
      'id': item.id,
      'operationType': _operationToJson[item.operationType],
      'payload': base64Encode(item.payload),
      'status': _statusToJson[item.status],
      'retryCount': item.retryCount,
      'createdAt': item.createdAt.microsecondsSinceEpoch,
      'lastAttemptAt': item.lastAttemptAt?.microsecondsSinceEpoch,
    };

const Map<SyncOperationType, String> _operationToJson = {
  SyncOperationType.create: 'create',
  SyncOperationType.update: 'update',
  SyncOperationType.delete: 'delete',
};

const Map<SyncQueueStatus, String> _statusToJson = {
  SyncQueueStatus.pending: 'pending',
  SyncQueueStatus.inProgress: 'in_progress',
  SyncQueueStatus.success: 'success',
  SyncQueueStatus.failed: 'failed',
};

SyncQueueItem _itemFromJson(Object? raw) {
  if (raw is! Map<String, dynamic>) {
    throw const FormatException('Queue backup item must be an object');
  }
  final id = raw['id'];
  if (id is! String || id.isEmpty) {
    throw const FormatException('Queue backup item "id" must be a non-empty '
        'string');
  }

  final operation = raw['operationType'];
  if (operation is! String || !_operationFromJson.containsKey(operation)) {
    throw FormatException('Unknown queue backup operationType: $operation');
  }

  final payloadB64 = raw['payload'];
  if (payloadB64 is! String) {
    throw const FormatException('Queue backup item "payload" must be a base64 '
        'string');
  }
  final Uint8List payload;
  try {
    payload = base64Decode(payloadB64);
  } on FormatException {
    throw const FormatException('Queue backup item "payload" is not valid '
        'base64');
  }

  final status = raw['status'];
  if (status is! String || !_statusFromJson.containsKey(status)) {
    throw FormatException('Unknown queue backup status: $status');
  }

  final retryCount = raw['retryCount'];
  if (retryCount is! int || retryCount < 0) {
    throw const FormatException('Queue backup item "retryCount" must be a '
        'non-negative integer');
  }

  final createdAt = raw['createdAt'];
  if (createdAt is! int) {
    throw const FormatException('Queue backup item "createdAt" must be an '
        'epoch-microseconds integer');
  }

  final lastAttemptAt = raw['lastAttemptAt'];
  if (lastAttemptAt != null && lastAttemptAt is! int) {
    throw const FormatException('Queue backup item "lastAttemptAt" must be an '
        'epoch-microseconds integer or null');
  }

  return SyncQueueItem(
    id: id,
    operationType: _operationFromJson[operation]!,
    payload: payload,
    status: _statusFromJson[status]!,
    retryCount: retryCount,
    createdAt: DateTime.fromMicrosecondsSinceEpoch(createdAt),
    lastAttemptAt: lastAttemptAt == null
        ? null
        : DateTime.fromMicrosecondsSinceEpoch(lastAttemptAt as int),
  );
}

const Map<String, SyncOperationType> _operationFromJson = {
  'create': SyncOperationType.create,
  'update': SyncOperationType.update,
  'delete': SyncOperationType.delete,
};

const Map<String, SyncQueueStatus> _statusFromJson = {
  'pending': SyncQueueStatus.pending,
  'in_progress': SyncQueueStatus.inProgress,
  'success': SyncQueueStatus.success,
  'failed': SyncQueueStatus.failed,
};
