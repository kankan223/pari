import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/repository/domain/conflict_resolution.dart';

/// VERIFY (Task 5.2): deterministic conflict-resolution hooks — the default
/// server-authoritative last-write-wins policy must be fully deterministic.
void main() {
  const policy = ServerAuthoritativeLastWriteWins();

  MutationVersion v({
    String entity = 'msg-1',
    DateTime? ts,
    bool serverAck = false,
    String author = 'hash-a',
  }) =>
      MutationVersion(
        entityId: entity,
        timestamp: ts ?? DateTime(2026, 8, 4, 12),
        serverAcknowledged: serverAck,
        authorHash: author,
      );

  group('ServerAuthoritativeLastWriteWins - ordering rules', () {
    test('server-acknowledged version beats a local-only version', () {
      final local = v(ts: DateTime(2026, 8, 4, 13), serverAck: false);
      final remote = v(ts: DateTime(2026, 8, 4, 11), serverAck: true);

      final result = policy.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyRemote);
      expect(result.winner, same(remote));
    });

    test('local-only version loses to ANY server-acknowledged version', () {
      final local = v(ts: DateTime(2026, 8, 4, 13), serverAck: false);
      final remote = v(ts: DateTime(2026, 8, 4, 10), serverAck: true);

      expect(
        policy.resolve(local: local, remote: remote).decision,
        ConflictDecision.applyRemote,
      );
    });

    test('newer of two non-acknowledged versions wins', () {
      final local = v(ts: DateTime(2026, 8, 4, 10));
      final remote = v(ts: DateTime(2026, 8, 4, 11));

      final result = policy.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyRemote);
    });

    test('newer of two server-acknowledged versions wins', () {
      final local = v(ts: DateTime(2026, 8, 4, 12), serverAck: true);
      final remote = v(ts: DateTime(2026, 8, 4, 14), serverAck: true);

      final result = policy.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyRemote);
      expect(result.winner, same(remote));
    });

    test('older local loses when remote is newer and acknowledged', () {
      final local = v(ts: DateTime(2026, 8, 4, 9), serverAck: false);
      final remote = v(ts: DateTime(2026, 8, 4, 12), serverAck: true);

      expect(
        policy.resolve(local: local, remote: remote).decision,
        ConflictDecision.applyRemote,
      );
    });
  });

  group('ServerAuthoritativeLastWriteWins - deterministic tiebreak', () {
    test('identical timestamps break deterministically on author hash', () {
      final ts = DateTime(2026, 8, 4, 12);
      final a = v(ts: ts, author: 'hash-a');
      final b = v(ts: ts, author: 'hash-b');

      final forward = policy.resolve(local: a, remote: b);
      final reversed = policy.resolve(local: b, remote: a);

      // The SAME version wins regardless of argument order — replicas
      // cannot disagree.
      expect(forward.winner, reversed.winner);
      // 'hash-b' > 'hash-a' so b wins both ways.
      expect(forward.winner, same(b));
      expect(reversed.winner, same(b));
    });

    test('resolution is deterministic across repeated calls', () {
      final local = v(ts: DateTime(2026, 8, 4, 12), author: 'hash-z');
      final remote = v(ts: DateTime(2026, 8, 4, 12), author: 'hash-a');

      final first = policy.resolve(local: local, remote: remote);
      for (var i = 0; i < 10; i++) {
        final again = policy.resolve(local: local, remote: remote);
        expect(again.decision, first.decision);
        expect(again.winner, first.winner);
      }
    });
  });

  group('ServerAuthoritativeLastWriteWins - out-of-order mutations (Task 5.5)',
      () {
    test('a newer LOCAL edit beats an older remote version of same authority',
        () {
      // Two devices both synced (both acknowledged), then device A edited
      // at 14:00 but device B (already synced) reports its 13:00 version on
      // a later push. Equal authority → newer local timestamp wins.
      final local = v(ts: DateTime(2026, 8, 4, 14), serverAck: true);
      final remote = v(ts: DateTime(2026, 8, 4, 13), serverAck: true);

      final result = policy.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyLocal);
      expect(result.winner, same(local));
    });

    test('an OLDER local edit loses to a newer remote version (no regress)',
        () {
      // Device A's edit at 13:00 collides with device B's newer 15:00
      // version that arrived while A was offline.
      final local = v(ts: DateTime(2026, 8, 4, 13), serverAck: false);
      final remote = v(ts: DateTime(2026, 8, 4, 15), serverAck: true);

      final result = policy.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyRemote);
    });
  });

  group('MaxMergePolicy - deterministic aggregate merge (Task 5.5)', () {
    const mergePolicy = MaxMergePolicy();

    test('merges to the higher karma score', () {
      expect(mergePolicy.merge(10, 24), 24);
      expect(mergePolicy.merge(24, 10), 24);
    });

    test('is commutative - argument order never matters', () {
      for (var i = 0; i < 20; i++) {
        final a = i * 3;
        final b = (i * 7) % 13;
        expect(mergePolicy.merge(a, b), mergePolicy.merge(b, a));
      }
    });

    test('is idempotent - merging a value with itself never double counts', () {
      expect(mergePolicy.merge(42, 42), 42);
    });

    test('null side contributes nothing', () {
      expect(mergePolicy.merge(null, 7), 7);
      expect(mergePolicy.merge(7, null), 7);
      expect(mergePolicy.merge(null, null), isNull);
    });

    test('is associative - multi-device convergence is order-independent', () {
      // Three devices converge on the same score regardless of merge order.
      const scores = [3, 9, 5];
      final left =
          mergePolicy.merge(mergePolicy.merge(scores[0], scores[1]), scores[2]);
      final right =
          mergePolicy.merge(scores[0], mergePolicy.merge(scores[1], scores[2]));
      expect(left, right);
      expect(left, 9);
    });
  });

  group('MergeAwareLastWriteWins - aggregate merge vs LWW (Task 5.5)', () {
    const mergeAware = MergeAwareLastWriteWins();

    MutationVersion withValue(num? value,
            {String entity = 'peer-1',
            DateTime? ts,
            bool serverAck = false,
            String author = 'hash-a'}) =>
        MutationVersion(
          entityId: entity,
          timestamp: ts ?? DateTime(2026, 8, 4, 12),
          serverAcknowledged: serverAck,
          authorHash: author,
          value: value,
        );

    test('merges when BOTH sides carry an aggregate for the same entity', () {
      final local = withValue(10, ts: DateTime(2026, 8, 4, 13));
      final remote = withValue(24, ts: DateTime(2026, 8, 4, 11));

      final result = mergeAware.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.merge);
      expect(result.mergedValue, 24);
      // Winner is the version that contributed the merged value.
      expect(result.winner, same(remote));
    });

    test('merge is order-independent (replicas cannot disagree)', () {
      final a = withValue(10, ts: DateTime(2026, 8, 4, 13), author: 'hash-a');
      final b = withValue(24, ts: DateTime(2026, 8, 4, 11), author: 'hash-b');

      final forward = mergeAware.resolve(local: a, remote: b);
      final reversed = mergeAware.resolve(local: b, remote: a);

      expect(forward.decision, ConflictDecision.merge);
      expect(forward.mergedValue, reversed.mergedValue);
    });

    test('merging with a stale value still preserves every increment', () {
      // Device A saw 30; device B (stale, 20) merges in later.
      final fresh = withValue(30);
      final stale = withValue(20);

      final result = mergeAware.resolve(local: fresh, remote: stale);

      expect(result.decision, ConflictDecision.merge);
      expect(result.mergedValue, 30);
    });

    test('falls back to plain LWW when either side lacks an aggregate', () {
      // Simple-field edit: no values → base LWW applies unchanged.
      final local = v(ts: DateTime(2026, 8, 4, 10));
      final remote = v(ts: DateTime(2026, 8, 4, 12), serverAck: true);

      final result = mergeAware.resolve(local: local, remote: remote);

      expect(result.decision, ConflictDecision.applyRemote);
      expect(result.mergedValue, isNull);
    });

    test('a server-acknowledged aggregate beats an unacknowledged one', () {
      // Server already persisted 24; a local-only 10 is a stale read.
      final local = withValue(10, serverAck: false);
      final remote = withValue(24, serverAck: true);

      final result = mergeAware.resolve(local: local, remote: remote);

      // Both carry values → merged to the higher (24) rather than blindly
      // overwriting with the local 10.
      expect(result.decision, ConflictDecision.merge);
      expect(result.mergedValue, 24);
    });
  });

  group('multi-device convergence simulation (Task 5.5)', () {
    // Three devices each edit the same karma aggregate concurrently; every
    // pairwise merge order must converge on the same value and decision.
    const mergeAware = MergeAwareLastWriteWins();

    test('all merge orders converge on the same karma score', () {
      final d1 = MutationVersion(
        entityId: 'peer-1',
        timestamp: DateTime(2026, 8, 4, 12),
        serverAcknowledged: false,
        authorHash: 'hash-d1',
        value: 7,
      );
      final d2 = MutationVersion(
        entityId: 'peer-1',
        timestamp: DateTime(2026, 8, 4, 12),
        serverAcknowledged: false,
        authorHash: 'hash-d2',
        value: 5,
      );
      final d3 = MutationVersion(
        entityId: 'peer-1',
        timestamp: DateTime(2026, 8, 4, 12),
        serverAcknowledged: false,
        authorHash: 'hash-d3',
        value: 11,
      );

      // Pairwise merge in every order — associativity + commutativity means
      // the intermediate merged values are equal regardless of order.
      final m12 = mergeAware.resolve(local: d1, remote: d2).mergedValue!;
      final m23 = mergeAware.resolve(local: d2, remote: d3).mergedValue!;
      final m13 = mergeAware.resolve(local: d1, remote: d3).mergedValue!;

      // (d1∨d2) then ∨d3 == d1 then (d2∨d3)
      final left = mergeAware
          .resolve(
            local: MutationVersion(
              entityId: 'peer-1',
              timestamp: DateTime(2026, 8, 4, 12),
              serverAcknowledged: false,
              authorHash: 'hash-m',
              value: m12,
            ),
            remote: d3,
          )
          .mergedValue!;
      final right = mergeAware
          .resolve(
            local: d1,
            remote: MutationVersion(
              entityId: 'peer-1',
              timestamp: DateTime(2026, 8, 4, 12),
              serverAcknowledged: false,
              authorHash: 'hash-m',
              value: m23,
            ),
          )
          .mergedValue!;

      expect(left, 11);
      expect(right, 11);
      expect(m13, 11);
    });

    test('an identical-timestamp local-vs-remote LWW tie converges', () {
      // Non-aggregate (value-less) edits at the exact same instant across two
      // devices: the author-hash tiebreak must pick the SAME winner on both.
      final ts = DateTime(2026, 8, 4, 12);
      final deviceA = MutationVersion(
        entityId: 'msg-1',
        timestamp: ts,
        serverAcknowledged: false,
        authorHash: 'aaaa',
      );
      final deviceB = MutationVersion(
        entityId: 'msg-1',
        timestamp: ts,
        serverAcknowledged: false,
        authorHash: 'bbbb',
      );

      final fromA = policy.resolve(local: deviceA, remote: deviceB);
      final fromB = policy.resolve(local: deviceB, remote: deviceA);

      expect(fromA.winner, same(deviceB));
      expect(fromB.winner, same(deviceB));
    });
  });
}
