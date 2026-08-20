import 'dart:typed_data';

import 'package:civic_commons/transparency/data/in_memory_transparency_repository.dart';
import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — Transparency log chain integrity integration: append records
/// across multiple pin-code scopes → verify per-scope integrity → tamper
/// detection. Uses the REAL InMemoryTransparencyRepository.
void main() {
  group('Task 13.2 — transparency chain integrity integration', () {
    late InMemoryTransparencyRepository repo;
    late _DeterministicHasher hasher;

    setUp(() {
      hasher = _DeterministicHasher();
      repo = InMemoryTransparencyRepository(hasher: hasher);
    });

    Future<TransparencyRecord> makeRecord({
      required int seq,
      required String id,
      required TransparencyAction action,
      required String summary,
      required String pinCode,
      required String prevHash,
    }) async {
      final r = TransparencyRecord(
        seq: seq,
        recordId: id,
        action: action,
        summary: summary,
        pinCode: pinCode,
        occurredAt: DateTime.utc(2026, 8, 20, 12, seq),
        prevHash: prevHash,
        selfHash: '',
      );
      final hash = await r.computeSelfHash(hasher);
      return TransparencyRecord(
        seq: r.seq,
        recordId: r.recordId,
        action: r.action,
        summary: r.summary,
        pinCode: r.pinCode,
        occurredAt: r.occurredAt,
        prevHash: r.prevHash,
        selfHash: hash,
      );
    }

    test('single scope chain: 5 records → integrity passes', () async {
      var prevHash = TransparencyRecord.genesisHash;
      for (var i = 0; i < 5; i++) {
        final record = await makeRecord(
          seq: i,
          id: 't-$i',
          action: TransparencyAction.moderationAction,
          summary: 'Record $i',
          pinCode: '110001',
          prevHash: prevHash,
        );
        await repo.append(record);
        prevHash = record.selfHash;
      }

      expect(await repo.getCount('110001'), 5);
      expect(await repo.verifyIntegrity('110001'), isTrue);
    });

    test('multi-scope isolation: different pin codes are independent chains',
        () async {
      final r0a = await makeRecord(
        seq: 0,
        id: 'a-0',
        action: TransparencyAction.moderationAction,
        summary: 'Scope A record 0',
        pinCode: '110001',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0a);

      final r0b = await makeRecord(
        seq: 0,
        id: 'b-0',
        action: TransparencyAction.accessRequest,
        summary: 'Scope B record 0',
        pinCode: '400001',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0b);

      final r1a = await makeRecord(
        seq: 1,
        id: 'a-1',
        action: TransparencyAction.contentReview,
        summary: 'Scope A record 1',
        pinCode: '110001',
        prevHash: r0a.selfHash,
      );
      await repo.append(r1a);

      expect(await repo.verifyIntegrity('110001'), isTrue);
      expect(await repo.verifyIntegrity('400001'), isTrue);
      expect(await repo.getCount('110001'), 2);
      expect(await repo.getCount('400001'), 1);
    });

    test('tamper detection: wrong prevHash breaks append', () async {
      final r0 = await makeRecord(
        seq: 0,
        id: 't-0',
        action: TransparencyAction.moderationAction,
        summary: 'Original',
        pinCode: '600001',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);

      final r1 = await makeRecord(
        seq: 1,
        id: 't-1',
        action: TransparencyAction.moderationAction,
        summary: 'Second',
        pinCode: '600001',
        prevHash: 'aa' * 32,
      );

      expect(() => repo.append(r1), throwsA(isA<StateError>()));
    });

    test('empty scope has valid integrity', () async {
      expect(await repo.verifyIntegrity('999999'), isTrue);
      expect(await repo.getCount('999999'), 0);
    });

    test('records carry only non-PII fields', () async {
      final r0 = await makeRecord(
        seq: 0,
        id: 'pi-0',
        action: TransparencyAction.contentReview,
        summary: 'Post flagged for community review',
        pinCode: '110001',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);

      final records = await repo.getByPinCode('110001');
      final recordStr = records.first.toString().toLowerCase();
      expect(recordStr, isNot(contains('+91')));
      expect(recordStr, isNot(contains('@')));
      expect(recordStr, isNot(contains('phone')));
    });
  });
}

/// Deterministic hasher for integration tests that verify chain integrity.
/// Produces a content-based hash (same input → same output).
class _DeterministicHasher implements TransparencyHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    // Simple content-based hash: XOR-fold the bytes into 32 bytes.
    final result = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      result[i % 32] ^= bytes[i];
    }
    return result;
  }
}
