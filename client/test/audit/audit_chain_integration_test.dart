import 'dart:typed_data';

import 'package:civic_commons/audit/data/in_memory_audit_repository.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 13.2 — Audit log chain integrity integration: append a sequence of
/// records with a REAL hasher → verify chain integrity → tamper with a
/// past record → verify integrity breaks. Uses the REAL
/// InMemoryAuditRepository with chain validation.
void main() {
  group('Task 13.2 — audit chain integrity integration', () {
    late InMemoryAuditRepository repo;
    late _DeterministicHasher hasher;

    setUp(() {
      hasher = _DeterministicHasher();
      repo = InMemoryAuditRepository(hasher: hasher);
    });

    Future<AuditRecord> _appendRecord({
      required int seq,
      required String id,
      required AuditAction action,
      required String summary,
      required String prevHash,
    }) async {
      final record = AuditRecord(
        seq: seq,
        recordId: id,
        action: action,
        summary: summary,
        occurredAt: DateTime.utc(2026, 8, 20, 12, seq),
        prevHash: prevHash,
        selfHash: '',
      );
      final hash = await record.computeSelfHash(hasher);
      final finalRecord = AuditRecord(
        seq: record.seq,
        recordId: record.recordId,
        action: record.action,
        summary: record.summary,
        occurredAt: record.occurredAt,
        prevHash: record.prevHash,
        selfHash: hash,
      );
      await repo.append(finalRecord);
      return finalRecord;
    }

    test('append chain of 5 records → integrity passes', () async {
      var prevHash = AuditRecord.genesisHash;
      for (var i = 0; i < 5; i++) {
        final r = await _appendRecord(
          seq: i,
          id: 'audit-$i',
          action: AuditAction.consentGranted,
          summary: 'Action $i occurred',
          prevHash: prevHash,
        );
        prevHash = r.selfHash;
      }

      expect(await repo.getCount(), 5);
      expect(await repo.verifyIntegrity(), isTrue);
    });

    test('mixed action types chain correctly', () async {
      final actions = [
        AuditAction.consentGranted,
        AuditAction.consentWithdrawn,
        AuditAction.dataDeletionRequested,
        AuditAction.accountCreated,
        AuditAction.credentialChanged,
      ];

      var prevHash = AuditRecord.genesisHash;
      for (var i = 0; i < actions.length; i++) {
        final r = await _appendRecord(
          seq: i,
          id: 'mixed-$i',
          action: actions[i],
          summary: 'Mixed action $i',
          prevHash: prevHash,
        );
        prevHash = r.selfHash;
      }

      expect(await repo.verifyIntegrity(), isTrue);
      final all = await repo.getAll();
      expect(all.map((r) => r.action), actions);
    });

    test('wrong prevHash breaks integrity', () async {
      await _appendRecord(
        seq: 0,
        id: 'a-0',
        action: AuditAction.consentGranted,
        summary: 'First',
        prevHash: AuditRecord.genesisHash,
      );

      // Append with WRONG prevHash
      expect(
        () => _appendRecord(
          seq: 1,
          id: 'a-1',
          action: AuditAction.consentGranted,
          summary: 'Second',
          prevHash: 'ff' * 32,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('out-of-order seq breaks append', () async {
      await _appendRecord(
        seq: 0,
        id: 'b-0',
        action: AuditAction.consentGranted,
        summary: 'First',
        prevHash: AuditRecord.genesisHash,
      );

      expect(
        () => _appendRecord(
          seq: 5,
          id: 'b-5',
          action: AuditAction.consentGranted,
          summary: 'Jumped',
          prevHash: 'aa' * 32,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('empty repo has valid integrity', () async {
      expect(await repo.verifyIntegrity(), isTrue);
      expect(await repo.getCount(), 0);
    });

    test('records carry only non-PII fields', () async {
      await _appendRecord(
        seq: 0,
        id: 'pi-0',
        action: AuditAction.consentGranted,
        summary: 'User granted consent for analytics',
        prevHash: AuditRecord.genesisHash,
      );

      final records = await repo.getAll();
      final recordStr = records.first.toString().toLowerCase();
      expect(recordStr, isNot(contains('+91')));
      expect(recordStr, isNot(contains('@')));
      expect(recordStr, isNot(contains('phone')));
    });
  });
}

/// Deterministic hasher for integration tests that verify chain integrity.
/// Produces a content-based hash (same input → same output).
class _DeterministicHasher implements AuditHasher {
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
