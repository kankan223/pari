import 'dart:typed_data';

import '../domain/entity_store.dart';
import '../domain/idempotency_key.dart';
import '../domain/queue_payload_cipher.dart';
import '../domain/sync_queue_item.dart';
import '../domain/sync_queue_repository.dart';

/// Local [SyncQueueRepository] (data layer).
///
/// Backed by an [EntityStore] (the encrypted SQLCipher database) and a
/// [QueuePayloadCipher].
///
/// SECURITY CHECKPOINT (Task 3.3): every payload is sealed with the cipher
/// BEFORE it is inserted — the queue never persists plaintext mutation
/// payloads. This is the ONLY outbound path for local mutations: nothing is
/// ever sent anywhere except by draining [getPending] through the injected
/// [SyncSink].
class LocalSyncQueueRepository implements SyncQueueRepository {
  /// Hard cap on queued mutations (Task 5.6, master plan: max 1000 items).
  ///
  /// When the queue exceeds this on an insert, the OLDEST non-in-flight items
  /// are evicted first (FIFO) so a runaway backlog cannot grow unbounded on
  /// disk. In-flight items are never evicted — a push in progress is
  /// protected (bounded overage by the in-flight batch, ≤10).
  static const int defaultMaxQueueSize = 1000;

  final EntityStore<SyncQueueItem> _store;
  final QueuePayloadCipher _cipher;
  final IdempotencyKeyGenerator _idGen;
  final DateTime Function() _clock;
  final int _maxQueueSize;

  LocalSyncQueueRepository({
    required EntityStore<SyncQueueItem> store,
    required QueuePayloadCipher cipher,
    IdempotencyKeyGenerator? idempotencyKeys,
    DateTime Function()? clock,
    int maxQueueSize = defaultMaxQueueSize,
  })  : _store = store,
        _cipher = cipher,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _clock = clock ?? DateTime.now,
        _maxQueueSize = maxQueueSize {
    if (maxQueueSize < 1) {
      throw ArgumentError.value(
          maxQueueSize, 'maxQueueSize', 'must be at least 1');
    }
  }

  @override
  Future<SyncQueueItem> enqueue({
    required SyncOperationType operationType,
    required Uint8List payload,
  }) {
    // create() seals the payload before storage (single enforcement point).
    return create(
      SyncQueueItem(
        id: _nextId(),
        operationType: operationType,
        payload: payload,
        createdAt: DateTime.now(),
      ),
    );
  }

  @override
  Future<SyncQueueItem> create(SyncQueueItem item) async {
    // SECURITY CHECKPOINT (Task 3.3): seal BEFORE storage — the store only
    // ever sees ciphertext, regardless of the insertion path.
    final sealed = await _cipher.seal(item.payload);
    final queued = SyncQueueItem(
      id: item.id,
      operationType: item.operationType,
      payload: sealed,
      status: SyncQueueStatus.pending,
      retryCount: item.retryCount,
      createdAt: item.createdAt,
    );
    await _store.insert(queued);
    // Task 5.6: bound the queue size (FIFO eviction of the oldest non-flight
    // items) so the encrypted queue cannot grow without limit. The
    // just-inserted item is passed by id so it is excluded from eviction
    // candidates BY CONSTRUCTION — its survival never depends on sort order.
    await _enforceCap(excludeId: queued.id);
    return queued;
  }

  /// FIFO eviction: keeps the queue at ≤ [_maxQueueSize] by deleting the
  /// oldest non-`in_progress` items first (master plan: max 1000, FIFO
  /// eviction). [excludeId] (the item that triggered the cap) is never a
  /// candidate, so a just-inserted item always survives — even when its
  /// `createdAt` ties with an older item's (Dart's [List.sort] is not
  /// guaranteed stable, so ties are decided by exclusion, not ordering).
  Future<void> _enforceCap({required String excludeId}) async {
    final all = await _store.getAll();
    if (all.length <= _maxQueueSize) {
      return;
    }
    final evictable = all
        .where((i) => i.status != SyncQueueStatus.inProgress)
        .where((i) => i.id != excludeId)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    final toEvict = all.length - _maxQueueSize;
    for (final item in evictable.take(toEvict)) {
      await _store.delete(item.id);
    }
  }

  @override
  Future<int> purgeExpired({
    DateTime? now,
    Duration maxAge = const Duration(days: 30),
  }) async {
    final cutoff = (now ?? _clock()).subtract(maxAge);
    final all = await _store.getAll();
    var purged = 0;
    for (final item in all) {
      // Strictly older than the cutoff (an item exactly maxAge old survives).
      if (item.createdAt.isBefore(cutoff)) {
        await _store.delete(item.id);
        purged++;
      }
    }
    return purged;
  }

  @override
  Future<SyncQueueItem?> getById(String id) => _store.getById(id);

  @override
  Future<List<SyncQueueItem>> getAll() => _store.getAll();

  @override
  Future<SyncQueueItem> update(SyncQueueItem item) async {
    // Status-transition path: the payload is preserved as stored (already
    // sealed) — callers must pass a copyWith of a stored item, never a raw
    // payload.
    await _store.update(item);
    return item;
  }

  @override
  Future<void> delete(String id) => _store.delete(id);

  @override
  Future<List<SyncQueueItem>> getPending() async {
    final all = await _store.getAll();
    final pending =
        all.where((i) => i.status == SyncQueueStatus.pending).toList();
    // Oldest first — stable, deterministic drain order.
    pending.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return pending;
  }

  @override
  Future<List<SyncQueueItem>> getRetryable({
    required DateTime now,
    required Duration Function(int retryCount) retryDelay,
  }) {
    return _store.getAll().then((all) {
      final eligible =
          all.where((i) => i.status == SyncQueueStatus.failed).where((i) {
        final last = i.lastAttemptAt;
        if (last == null) {
          return true; // never attempted → immediately retryable
        }
        final dueAt = last.add(retryDelay(i.retryCount));
        return !now.isBefore(dueAt);
      }).toList();
      eligible.sort((a, b) => a.createdAt.compareTo(b.createdAt));
      return eligible;
    });
  }

  @override
  Future<void> markInProgress(String id) async {
    final item = await _store.getById(id);
    if (item == null) {
      return;
    }
    await _store.update(
      item.copyWith(
          status: SyncQueueStatus.inProgress, lastAttemptAt: _clock()),
    );
  }

  @override
  Future<void> markSuccess(String id) async {
    final item = await _store.getById(id);
    if (item == null) {
      return;
    }
    await _store.update(item.copyWith(status: SyncQueueStatus.success));
  }

  @override
  Future<void> markFailed(String id) async {
    final item = await _store.getById(id);
    if (item == null) {
      return;
    }
    await _store.update(
      item.copyWith(
        status: SyncQueueStatus.failed,
        retryCount: item.retryCount + 1,
      ),
    );
  }

  @override
  Future<void> recoverInterrupted() async {
    final all = await _store.getAll();
    for (final item in all) {
      if (item.status == SyncQueueStatus.inProgress) {
        await _store.update(item.copyWith(status: SyncQueueStatus.pending));
      }
    }
  }

  /// Fresh UUID v4 id — doubles as the idempotency key the sync transport
  /// attaches to the `Idempotency-Key` header (Task 5.2/5.3).
  String _nextId() => _idGen.generate();
}
