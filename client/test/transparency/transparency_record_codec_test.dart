import 'package:civic_commons/transparency/data/transparency_record_codec.dart';
import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransparencyRecordCodec', () {
    test('encode/decode round-trip preserves all fields', () {
      final original = TransparencyRecord(
        seq: 3,
        recordId: 'rec-003',
        action: TransparencyAction.contentReview,
        summary: 'Content reviewed and approved',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 14, 30),
        prevHash: 'aaa111',
        selfHash: 'bbb222',
      );

      final row = TransparencyRecordCodec.encode(original);
      final decoded = TransparencyRecordCodec.decode(row);

      expect(decoded.seq, original.seq);
      expect(decoded.recordId, original.recordId);
      expect(decoded.action, original.action);
      expect(decoded.summary, original.summary);
      expect(decoded.pinCode, original.pinCode);
      expect(decoded.occurredAt, original.occurredAt);
      expect(decoded.prevHash, original.prevHash);
      expect(decoded.selfHash, original.selfHash);
    });

    test('decode throws FormatException for missing columns', () {
      final row = <String, Object?>{
        'record_id': 'rec-004',
        // missing seq, action, summary, etc.
      };

      expect(
        () => TransparencyRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for unknown action wire code', () {
      final row = {
        'record_id': 'rec-005',
        'seq': 0,
        'action': 'unknown_action',
        'summary': 'Test',
        'pin_code': '800001',
        'occurred_at': DateTime.utc(2026, 8, 18).millisecondsSinceEpoch,
        'prev_hash': TransparencyRecord.genesisHash,
        'self_hash': 'abc',
      };

      expect(
        () => TransparencyRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('encode produces correct column names', () {
      final record = TransparencyRecord(
        seq: 0,
        recordId: 'rec-006',
        action: TransparencyAction.systemEvent,
        summary: 'System event',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 12),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: 'abc',
      );

      final row = TransparencyRecordCodec.encode(record);
      expect(row.containsKey('seq'), true);
      expect(row.containsKey('record_id'), true);
      expect(row.containsKey('action'), true);
      expect(row.containsKey('summary'), true);
      expect(row.containsKey('pin_code'), true);
      expect(row.containsKey('occurred_at'), true);
      expect(row.containsKey('prev_hash'), true);
      expect(row.containsKey('self_hash'), true);
    });
  });
}
