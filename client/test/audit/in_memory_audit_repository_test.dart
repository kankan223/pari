import 'dart:typed_data';

import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryAuditRepository', () {
    late InMemoryAuditRepository repo;

    setUp(() {
      repo = InMemoryAuditRepository();
    });

    AuditRecord makeRecord({
      int seq = 0,
      String recordId = 'audit-001',
      AuditAction action = AuditAction.consentGranted,
      String summary = 'Test summary',
      String prevHash = AuditRecord.genesisHash,
    }) {
      return AuditRecord(
        seq: seq,
        recordId: recordId,
        action: action,
        summary: summary,
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: prevHash,
        selfHash: 'self_hash_$seq',
      );
    }

    test('getAll returns empty list initially', () async {
      final records = await repo.getAll();
      expect(records, isEmpty);
    });

    test('getCount returns 0 initially', () async {
      expect(await repo.getCount(), 0);
    });

    test('append adds a record', () async {
      await repo.append(makeRecord());
      expect(await repo.getCount(), 1);
      final records = await repo.getAll();
      expect(records.length, 1);
      expect(records.first.recordId, 'audit-001');
    });

    test('append validates seq is next-in-seq', () async {
      await repo.append(makeRecord(seq: 0));
      expect(
        () => repo.append(makeRecord(seq: 2)),
        throwsStateError,
      );
    });

    test('append validates prevHash links to chain', () async {
      final first = makeRecord(seq: 0);
      await repo.append(first);

      final second = makeRecord(
        seq: 1,
        prevHash: 'wrong_hash',
      );
      expect(
        () => repo.append(second),
        throwsStateError,
      );
    });

    test('append accepts correct prevHash', () async {
      final first = makeRecord(seq: 0);
      await repo.append(first);

      final second = makeRecord(
        seq: 1,
        prevHash: first.selfHash,
      );
      await repo.append(second);
      expect(await repo.getCount(), 2);
    });

    test('append genesis record requires genesisHash prevHash', () async {
      expect(
        () => repo.append(makeRecord(prevHash: 'not_genesis')),
        throwsStateError,
      );
    });

    test('verifyIntegrity returns true for empty log', () async {
      expect(await repo.verifyIntegrity(), true);
    });

    test('verifyIntegrity returns true for valid chain', () async {
      final hasher = _FixedHasher();
      // Pre-compute a record's selfHash by creating a temp record
      final tempRecord = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Test',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: '',
      );
      final correctHash = await tempRecord.computeSelfHash(hasher);

      final repoWithHasher = InMemoryAuditRepository(hasher: hasher);
      final record = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Test',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: correctHash,
      );
      await repoWithHasher.append(record);
      expect(await repoWithHasher.verifyIntegrity(), true);
    });

    test('getAll returns records in order', () async {
      await repo.append(makeRecord(seq: 0, recordId: 'first'));
      await repo.append(makeRecord(
        seq: 1,
        recordId: 'second',
        prevHash: 'self_hash_0',
      ));
      await repo.append(makeRecord(
        seq: 2,
        recordId: 'third',
        prevHash: 'self_hash_1',
      ));

      final records = await repo.getAll();
      expect(records.length, 3);
      expect(records[0].recordId, 'first');
      expect(records[1].recordId, 'second');
      expect(records[2].recordId, 'third');
    });
  });
}

class _FixedHasher implements AuditHasher {
  String cachedHash = '';

  @override
  Future<Uint8List> hash(List<int> bytes) async {
    final hashBytes = Uint8List.fromList(
      List.generate(32, (i) => bytes.length + i),
    );
    cachedHash =
        hashBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return hashBytes;
  }
}
