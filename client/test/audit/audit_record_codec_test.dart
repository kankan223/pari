import 'package:civic_commons/audit/data/audit_record_codec.dart';
import 'package:civic_commons/audit/domain/audit_action.dart';
import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AuditRecordCodec', () {
    test('encode produces correct map', () {
      final record = AuditRecord(
        seq: 5,
        recordId: 'r1',
        action: AuditAction.consentGranted,
        summary: 'User granted consent',
        occurredAt: DateTime.utc(2026, 8, 19, 12),
        prevHash: 'prev_abc',
        selfHash: 'self_def',
      );

      final row = AuditRecordCodec.encode(record);
      expect(row['record_id'], 'r1');
      expect(row['seq'], 5);
      expect(row['action'], 'consentGranted');
      expect(row['summary'], 'User granted consent');
      expect(row['occurred_at'], DateTime.utc(2026, 8, 19, 12).millisecondsSinceEpoch);
      expect(row['prev_hash'], 'prev_abc');
      expect(row['self_hash'], 'self_def');
    });

    test('decode round-trips correctly', () {
      final original = AuditRecord(
        seq: 3,
        recordId: 'r2',
        action: AuditAction.dataDeletionRequested,
        summary: 'Deletion requested',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: 'prev_xyz',
        selfHash: 'self_abc',
      );

      final row = AuditRecordCodec.encode(original);
      final decoded = AuditRecordCodec.decode(row);

      expect(decoded.recordId, original.recordId);
      expect(decoded.seq, original.seq);
      expect(decoded.action, original.action);
      expect(decoded.summary, original.summary);
      expect(decoded.occurredAt, original.occurredAt);
      expect(decoded.prevHash, original.prevHash);
      expect(decoded.selfHash, original.selfHash);
    });

    test('decode throws FormatException for missing columns', () {
      expect(
        () => AuditRecordCodec.decode({'record_id': 'r1'}),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for unknown action', () {
      final row = {
        'record_id': 'r1',
        'seq': 0,
        'action': 'unknown_action',
        'summary': 'Test',
        'occurred_at': 1723994400000,
        'prev_hash': 'prev',
        'self_hash': 'self',
      };

      expect(
        () => AuditRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for null values', () {
      final row = {
        'record_id': null,
        'seq': 0,
        'action': 'consentGranted',
        'summary': 'Test',
        'occurred_at': 1723994400000,
        'prev_hash': 'prev',
        'self_hash': 'self',
      };

      expect(
        () => AuditRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('round-trip for all action types', () {
      for (final action in AuditAction.values) {
        final record = AuditRecord(
          seq: 0,
          recordId: 'r-${action.name}',
          action: action,
          summary: 'Test ${action.name}',
          occurredAt: DateTime.utc(2026, 8, 19),
          prevHash: AuditRecord.genesisHash,
          selfHash: 'hash',
        );

        final row = AuditRecordCodec.encode(record);
        final decoded = AuditRecordCodec.decode(row);
        expect(decoded.action, action);
      }
    });
  });
}
