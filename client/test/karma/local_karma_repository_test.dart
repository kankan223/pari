import 'package:civic_commons/karma/data/karma_event_records.dart';
import 'package:civic_commons/karma/data/local_karma_repository.dart';
import 'package:civic_commons/karma/domain/karma_action.dart';
import 'package:civic_commons/repository/domain/entity_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory EntityStore fake (mirrors the harness/test-fake contract).
class _MemStore<T> implements EntityStore<T> {
  final String Function(T) _idOf;
  final Map<String, T> _items = {};

  _MemStore(this._idOf);

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
  Future<List<T>> getAll() async => List.unmodifiable(_items.values);
}

String _hash(int n) => n.toRadixString(16).padLeft(64, '0');

void main() {
  late _MemStore<KarmaEventRecord> store;
  late LocalKarmaRepository repo;

  setUp(() {
    store = _MemStore<KarmaEventRecord>((r) => r.eventId);
    repo = LocalKarmaRepository(store: store);
  });

  group('record — append-only ledger', () {
    test('empty ledger has balance 0 and no events', () async {
      expect(await repo.balance(), 0);
      expect(await repo.events(), isEmpty);
      expect(await repo.verifyIntegrity(), isTrue);
    });

    test('records accumulate the running balance', () async {
      final a = await repo.record(
          action: KarmaAction.academyModuleCompleted, actorHash: _hash(1));
      final b = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));

      expect(a.seq, 0);
      expect(a.balanceAfter, 2);
      expect(b.seq, 1);
      expect(b.balanceAfter, 7);
      expect(await repo.balance(), 7);
    });

    test('negative actions reduce the balance', () async {
      await repo.record(
          action: KarmaAction.ledgerPostRejected, actorHash: _hash(1));
      expect(await repo.balance(), -3);
    });

    test('chain links: prevHash → selfHash continuity', () async {
      final a = await repo.record(
          action: KarmaAction.warRoomAnalystVetted, actorHash: _hash(1));
      final b = await repo.record(
          action: KarmaAction.warRoomCaseContribution, actorHash: _hash(2));

      expect(a.prevHash, LocalKarmaRepository.zeroHash);
      expect(b.prevHash, a.selfHash);
      expect(a.selfHash.length, 64);
      expect(b.selfHash.length, 64);
    });

    test('event ids are UUID v4 (wire Idempotency-Key)', () async {
      final event = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      final pattern = RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$');
      expect(pattern.hasMatch(event.eventId), isTrue);
    });

    test('malformed actor hash is rejected (ArgumentError)', () async {
      await expectLater(
        repo.record(action: KarmaAction.ledgerPostVerified, actorHash: 'short'),
        throwsArgumentError,
      );
      await expectLater(
        repo.record(
            action: KarmaAction.ledgerPostVerified,
            actorHash: List.filled(64, 'g').join()),
        throwsArgumentError,
      );
    });

    test('actor hash is normalized to lowercase 64-hex', () async {
      final mixed = ('ab' * 32).toUpperCase();
      final event = await repo.record(
          action: KarmaAction.academyModuleCompleted, actorHash: mixed);
      expect(event.actorHash, 'ab' * 32);
    });
  });

  group('verifyIntegrity — tamper detection (SECURITY CHECKPOINT 10.2)', () {
    test('untouched chain verifies', () async {
      await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      await repo.record(
          action: KarmaAction.academyModuleCompleted, actorHash: _hash(1));
      expect(await repo.verifyIntegrity(), isTrue);
    });

    test('a mutated delta is detected', () async {
      final event = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      // Directly corrupt the stored row (bypassing the append API).
      final row = (await store.getById(event.eventId))!;
      await store.update(KarmaEventRecord(
        eventId: row.eventId,
        seq: row.seq,
        actorHash: row.actorHash,
        action: row.action,
        delta: 99,
        balanceAfter: row.balanceAfter,
        at: row.at,
        prevHash: row.prevHash,
        selfHash: row.selfHash,
      ));
      expect(await repo.verifyIntegrity(), isFalse);
    });

    test('a reordered chain is detected', () async {
      final a = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      final b = await repo.record(
          action: KarmaAction.academyModuleCompleted, actorHash: _hash(1));
      final ra = (await store.getById(a.eventId))!;
      final rb = (await store.getById(b.eventId))!;
      // Swap seq values → broken exactly-next-sequence invariant.
      await store.update(KarmaEventRecord(
        eventId: ra.eventId,
        seq: rb.seq,
        actorHash: ra.actorHash,
        action: ra.action,
        delta: ra.delta,
        balanceAfter: ra.balanceAfter,
        at: ra.at,
        prevHash: ra.prevHash,
        selfHash: ra.selfHash,
      ));
      await store.update(KarmaEventRecord(
        eventId: rb.eventId,
        seq: ra.seq,
        actorHash: rb.actorHash,
        action: rb.action,
        delta: rb.delta,
        balanceAfter: rb.balanceAfter,
        at: rb.at,
        prevHash: rb.prevHash,
        selfHash: rb.selfHash,
      ));
      expect(await repo.verifyIntegrity(), isFalse);
    });

    test('a removed middle event is detected', () async {
      final a = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      await repo.record(
          action: KarmaAction.academyModuleCompleted, actorHash: _hash(1));
      await repo.record(
          action: KarmaAction.warRoomAnalystVetted, actorHash: _hash(1));
      await store.delete(a.eventId); // drop the FIRST event → link break.
      expect(await repo.verifyIntegrity(), isFalse);
    });
  });

  group('cold-restart durability (offline-first)', () {
    test('a fresh repository over the same store sees the same ledger',
        () async {
      await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      await repo.record(
          action: KarmaAction.warRoomCaseContribution, actorHash: _hash(1));

      // Simulate app restart: a NEW repository instance over the SAME store.
      final restarted = LocalKarmaRepository(store: store);
      expect(await restarted.balance(), 20);
      expect((await restarted.events()).length, 2);
      expect(await restarted.verifyIntegrity(), isTrue);
    });
  });

  group('KarmaEventRecord.tryParse — read-path revalidation', () {
    test('round-trips a valid row', () {
      final record = KarmaEventRecord(
        eventId: '11111111-1111-4111-8111-111111111111',
        seq: 0,
        actorHash: _hash(1),
        action: KarmaAction.ledgerPostVerified,
        delta: 5,
        balanceAfter: 5,
        at: DateTime.utc(2026, 8, 18),
        prevHash: LocalKarmaRepository.zeroHash,
        selfHash: _hash(2),
      );
      final parsed = KarmaEventRecord.tryParse(
        eventId: record.eventId,
        seq: record.seq,
        actorHash: record.actorHash,
        action: record.action.wireName,
        delta: record.delta,
        balanceAfter: record.balanceAfter,
        at: record.at,
        prevHash: record.prevHash,
        selfHash: record.selfHash,
      );
      expect(parsed, isNotNull);
      expect(parsed!.toEvent().action, KarmaAction.ledgerPostVerified);
    });

    test('delta that does not match the action is rejected', () {
      expect(
        KarmaEventRecord.tryParse(
          eventId: '11111111-1111-4111-8111-111111111111',
          seq: 0,
          actorHash: _hash(1),
          action: 'ledger_post_verified',
          delta: 99, // forged
          balanceAfter: 5,
          at: DateTime.utc(2026, 8, 18),
          prevHash: LocalKarmaRepository.zeroHash,
          selfHash: _hash(2),
        ),
        isNull,
      );
    });

    test('unknown action wire and non-64-hex hashes are rejected', () {
      expect(
        KarmaEventRecord.tryParse(
          eventId: '11111111-1111-4111-8111-111111111111',
          seq: 0,
          actorHash: _hash(1),
          action: 'bogus_action',
          delta: 5,
          balanceAfter: 5,
          at: DateTime.utc(2026, 8, 18),
          prevHash: LocalKarmaRepository.zeroHash,
          selfHash: _hash(2),
        ),
        isNull,
      );
      expect(
        KarmaEventRecord.tryParse(
          eventId: '11111111-1111-4111-8111-111111111111',
          seq: 0,
          actorHash: 'short',
          action: 'ledger_post_verified',
          delta: 5,
          balanceAfter: 5,
          at: DateTime.utc(2026, 8, 18),
          prevHash: LocalKarmaRepository.zeroHash,
          selfHash: _hash(2),
        ),
        isNull,
      );
    });
  });

  group('KarmaEvent canonical bytes', () {
    test('recomputeSelfHash reproduces the stored selfHash', () async {
      final event = await repo.record(
          action: KarmaAction.ledgerPostVerified, actorHash: _hash(1));
      final recomputed =
          await event.recomputeSelfHash(const RealKarmaSha256Hasher());
      expect(recomputed, event.selfHash);
    });
  });
}
