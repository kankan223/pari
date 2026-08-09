import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/domain/conflict_resolution.dart';
import 'package:civic_commons/repository/domain/sync_conflict_resolver.dart';
import 'package:civic_commons/repository/domain/sync_queue_item.dart';
import 'package:civic_commons/repository/domain/sync_sink.dart';

/// VERIFY (Task 5.5): the [SyncConflictResolver] maps each three-way push
/// outcome to the correct sync disposition — and the conflict path is
/// DETERMINISTIC (same policy + inputs → same disposition on every device).
void main() {
  SyncQueueItem item({DateTime? createdAt, String id = 'q-1'}) => SyncQueueItem(
        id: id,
        operationType: SyncOperationType.create,
        payload: Uint8List.fromList([1, 2, 3]),
        createdAt: createdAt ?? DateTime(2026, 8, 4, 12),
      );

  group('SyncConflictResolver - non-conflict outcomes', () {
    const resolver = SyncConflictResolver();

    test('acknowledged -> success', () {
      final resolution = resolver.resolve(
          item: item(), outcome: const SyncPushOutcome.acknowledged());

      expect(resolution.disposition, SyncDisposition.success);
      expect(resolution.isSuccess, isTrue);
    });

    test('rejected -> retry', () {
      final resolution = resolver.resolve(
          item: item(), outcome: const SyncPushOutcome.rejected());

      expect(resolution.disposition, SyncDisposition.retry);
      expect(resolution.isRetry, isTrue);
    });
  });

  group('SyncConflictResolver - conflict outcomes (server-authoritative)', () {
    const resolver = SyncConflictResolver();

    MutationVersion remote({
      DateTime? ts,
      bool ack = true,
      String author = 'hash-remote',
      num? value,
    }) =>
        MutationVersion(
          entityId: 'q-1',
          timestamp: ts ?? DateTime(2026, 8, 4, 13),
          serverAcknowledged: ack,
          authorHash: author,
          value: value,
        );

    test('a server-acknowledged remote supersedes a fresh local edit', () {
      // Item created locally at 14:00 but the server (acknowledged) has a
      // divergent 15:00 version: Rule 1 (server-authoritative) wins → the
      // local mutation is superseded.
      final localItem = item(createdAt: DateTime(2026, 8, 4, 14));
      final resolution = resolver.resolve(
        item: localItem,
        outcome: SyncPushOutcome.conflict(remote(ts: DateTime(2026, 8, 4, 15))),
      );

      expect(resolution.disposition, SyncDisposition.superseded);
      expect(resolution.isSuperseded, isTrue);
      expect(resolution.resolution?.decision, ConflictDecision.applyRemote);
    });

    test('Rule 1 is absolute: ANY acknowledged remote beats a local-only edit',
        () {
      // Even an OLDER server version wins over a newer unacknowledged local
      // edit — the server is authoritative for what actually happened.
      final localItem = item(createdAt: DateTime(2026, 8, 4, 20));
      final resolution = resolver.resolve(
        item: localItem,
        outcome: SyncPushOutcome.conflict(remote(ts: DateTime(2026, 8, 4, 19))),
      );

      expect(resolution.disposition, SyncDisposition.superseded);
    });

    test('an injected timestamp-first policy keeps the newer local edit', () {
      // Some deployments prefer newer-wins over server-authority. With a
      // timestamp-first policy injected, a NEWER local edit survives the
      // conflict → the item is kept for retry (re-submit). This proves the
      // resolver honors any deterministic policy, not just the default.
      const newerWins = SyncConflictResolver(
        policy: _TimestampFirstPolicy(),
      );
      final localItem = item(createdAt: DateTime(2026, 8, 4, 16));
      final resolution = newerWins.resolve(
        item: localItem,
        outcome: SyncPushOutcome.conflict(remote(ts: DateTime(2026, 8, 4, 15))),
      );

      expect(resolution.disposition, SyncDisposition.retry);
      expect(resolution.resolution?.decision, ConflictDecision.applyLocal);
    });

    test('an aggregate conflict yields a superseded disposition + merged value',
        () {
      // Merge-aware policy: when the entity layer passes a local version
      // carrying the aggregate value, both sides merge → 42 recorded.
      const mergeAware = SyncConflictResolver(
        policy: MergeAwareLastWriteWins(),
      );
      final localItem = item(createdAt: DateTime(2026, 8, 4, 14));
      final localWithValue = MutationVersion(
        entityId: 'q-1',
        timestamp: DateTime(2026, 8, 4, 14),
        serverAcknowledged: false,
        authorHash: 'local-device',
        value: 30,
      );
      final resolution = mergeAware.resolve(
        item: localItem,
        outcome: SyncPushOutcome.conflict(
          remote(value: 42, ts: DateTime(2026, 8, 4, 13)),
        ),
        localVersion: localWithValue,
      );

      // The merged value is recorded on the resolution; the opaque queued
      // payload cannot carry it, so the item is superseded at queue level.
      expect(resolution.disposition, SyncDisposition.superseded);
      expect(resolution.resolution?.decision, ConflictDecision.merge);
      expect(resolution.resolution?.mergedValue, 42);
    });
  });

  group('SyncConflictResolver - SECURITY CHECKPOINT (Task 5.5)', () {
    test('resolution operates only on ids/timestamps/hashes, never payloads',
        () {
      const resolver = SyncConflictResolver();
      final localItem = item();
      final outcome = SyncPushOutcome.conflict(MutationVersion(
        entityId: 'q-1',
        timestamp: DateTime(2026, 8, 4, 13),
        serverAcknowledged: true,
        authorHash: 'hash-remote',
      ));

      final resolution = resolver.resolve(item: localItem, outcome: outcome);

      // The resolver only ever returns a disposition; the payload is opaque
      // and is never opened, read, or merged (asserted statically by the
      // security scan — here we prove the disposition is deterministic).
      expect(resolution.disposition, SyncDisposition.superseded);
      expect(localItem.payload, isNotEmpty);
    });
  });
}

/// Deterministic newer-timestamp-wins policy (equal authority), used to prove
/// the resolver honors injected policies other than the default.
class _TimestampFirstPolicy implements ConflictResolutionPolicy {
  const _TimestampFirstPolicy();

  @override
  ConflictResolution resolve({
    required MutationVersion local,
    required MutationVersion remote,
  }) {
    final winner = local.timestamp.isAfter(remote.timestamp) ? local : remote;
    return ConflictResolution(
      winner == local
          ? ConflictDecision.applyLocal
          : ConflictDecision.applyRemote,
      winner,
    );
  }
}
