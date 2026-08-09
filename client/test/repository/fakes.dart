import 'dart:typed_data';

import 'package:civic_commons/crypto/crypto_service_impl.dart';
import 'package:civic_commons/repository/data/aes_gcm_queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/conflict_resolution.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:civic_commons/repository/domain/queue_payload_cipher.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_sink.dart';

/// In-memory [EntityStore] fake for unit tests.
class InMemoryEntityStore<T> implements EntityStore<T> {
  final String Function(T) _idOf;
  final Map<String, T> _items = {};

  InMemoryEntityStore(this._idOf);

  @override
  Future<void> insert(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> update(T entity) async {
    _items[_idOf(entity)] = entity;
  }

  @override
  Future<void> delete(String id) async {
    _items.remove(id);
  }

  @override
  Future<T?> getById(String id) async => _items[id];

  @override
  Future<List<T>> getAll() async => _items.values.toList(growable: false);

  int get length => _items.length;
}

/// A real AES-256-GCM [QueuePayloadCipher] with a fixed 32-byte test key.
///
/// Fast (no Argon2id), so unit tests can genuinely prove payloads are
/// encrypted before storage.
QueuePayloadCipher testCipher() => AesGcmQueuePayloadCipher(
      crypto: CryptoServiceImpl(),
      key: Uint8List.fromList(List.generate(32, (i) => i + 1)),
    );

/// Recording [SyncSink] fake — records every push and lets the test control
/// the acknowledgement result. Never performs actual network I/O.
class RecordingSyncSink implements SyncSink {
  final List<SyncQueueItem> pushed = [];

  /// When true, [push] acknowledges every item; when false it rejects them
  /// (retryable). For conflict scenarios use [scriptConflict] or override
  /// [scriptedOutcomes].
  bool acknowledge = true;

  /// When non-null, [push] returns this conflict outcome for every item
  /// (with the recorded remote version).
  MutationVersion? scriptConflict;

  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async {
    pushed.add(item);
    final conflict = scriptConflict;
    if (conflict != null) {
      return SyncPushOutcome.conflict(conflict);
    }
    return acknowledge
        ? const SyncPushOutcome.acknowledged()
        : const SyncPushOutcome.rejected();
  }
}

/// [SyncSink] that throws if the repository ever attempts a network call.
///
/// Used to prove [fetchLocal] performs zero outbound I/O.
class ExplodingSyncSink implements SyncSink {
  @override
  Future<SyncPushOutcome> push(SyncQueueItem item) async {
    throw StateError('Network must never be touched during local reads');
  }
}

/// Convenience: builds an in-memory queue store for [SyncQueueItem].
InMemoryEntityStore<SyncQueueItem> queueStore() =>
    InMemoryEntityStore((i) => i.id);

/// Convenience: a fresh pending queue item for seeding tests.
SyncQueueItem pendingItem(String id, {Uint8List? payload}) => SyncQueueItem(
      id: id,
      operationType: SyncOperationType.create,
      payload: payload ?? Uint8List.fromList(utf8(id)),
      createdAt: DateTime(2026, 8, 2, 12),
    );

Uint8List utf8(String s) => Uint8List.fromList(s.codeUnits);
