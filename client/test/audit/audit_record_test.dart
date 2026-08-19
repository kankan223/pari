import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditRecord', () {
    test('constructs with required fields', () {
      final record = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'User granted consent',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'abc123',
      );

      expect(record.seq, 0);
      expect(record.recordId, 'audit-001');
      expect(record.action, AuditAction.consentGranted);
      expect(record.summary, 'User granted consent');
    });

    test('genesisHash is 64 zeros', () {
      expect(AuditRecord.genesisHash.length, 64);
      expect(RegExp(r'^0{64}$').hasMatch(AuditRecord.genesisHash), true);
    });

    test('canonicalBytes excludes selfHash', () {
      final record = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'User granted consent',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'abc123',
      );

      final canonical = utf8.decode(record.canonicalBytes);
      final map = json.decode(canonical) as Map<String, dynamic>;

      expect(map.containsKey('self_hash'), false);
      expect(map['seq'], 0);
      expect(map['record_id'], 'audit-001');
      expect(map['action'], 'consentGranted');
      expect(map['summary'], 'User granted consent');
      expect(map['prev_hash'], AuditRecord.genesisHash);
    });

    test('canonicalBytes is deterministic', () {
      final record = AuditRecord(
        seq: 5,
        recordId: 'audit-005',
        action: AuditAction.dataDeletionRequested,
        summary: 'Data deletion requested',
        occurredAt: DateTime.utc(2026, 8, 19, 12),
        prevHash: 'prev_hash_123',
        selfHash: 'self_hash_456',
      );

      expect(record.canonicalBytes, record.canonicalBytes);
    });

    test('equality is based on seq and recordId', () {
      final a = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Summary A',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'hash_a',
      );
      final b = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentWithdrawn,
        summary: 'Summary B',
        occurredAt: DateTime.utc(2026, 8, 19, 12),
        prevHash: 'different',
        selfHash: 'hash_b',
      );

      expect(a == b, true);
    });

    test('different seq or recordId are not equal', () {
      final a = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Summary',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'hash',
      );
      final b = AuditRecord(
        seq: 1,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Summary',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'hash',
      );
      final c = AuditRecord(
        seq: 0,
        recordId: 'audit-002',
        action: AuditAction.consentGranted,
        summary: 'Summary',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: 'hash',
      );

      expect(a == b, false);
      expect(a == c, false);
    });

    test('computeSelfHash produces 64-hex string', () async {
      final record = AuditRecord(
        seq: 0,
        recordId: 'audit-001',
        action: AuditAction.consentGranted,
        summary: 'Test',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: AuditRecord.genesisHash,
        selfHash: '',
      );

      final hasher = _TestHasher();
      final hash = await record.computeSelfHash(hasher);

      expect(hash.length, 64);
      expect(RegExp(r'^[0-9a-f]{64}$').hasMatch(hash), true);
    });
  });
}

class _TestHasher implements AuditHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    return Uint8List.fromList(List.generate(32, (i) => i % 256));
  }
}
