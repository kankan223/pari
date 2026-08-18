import 'dart:convert';
import 'dart:typed_data';

import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TransparencyRecord', () {
    test('constructs with required fields', () {
      final record = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.moderationAction,
        summary: 'Post flagged for review',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: 'abc123',
      );

      expect(record.seq, 0);
      expect(record.recordId, 'rec-001');
      expect(record.action, TransparencyAction.moderationAction);
      expect(record.summary, 'Post flagged for review');
      expect(record.pinCode, '800001');
    });

    test('genesisHash is 64 zeros', () {
      expect(TransparencyRecord.genesisHash.length, 64);
      expect(TransparencyRecord.genesisHash, '0' * 64);
    });

    test('canonicalBytes is deterministic', () {
      final record = TransparencyRecord(
        seq: 1,
        recordId: 'rec-002',
        action: TransparencyAction.contentReview,
        summary: 'Content reviewed',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10, 30),
        prevHash: 'aaa',
        selfHash: 'bbb',
      );

      final bytes1 = record.canonicalBytes;
      final bytes2 = record.canonicalBytes;
      expect(bytes1, bytes2);
    });

    test('canonicalBytes does not include selfHash', () {
      final record = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.systemEvent,
        summary: 'System started',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: 'should_not_appear',
      );

      final decoded = json.decode(utf8.decode(record.canonicalBytes));
      expect(decoded.containsKey('self_hash'), false);
      expect(decoded.containsKey('selfHash'), false);
    });

    test('equality is based on seq and recordId', () {
      final a = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.moderationAction,
        summary: 'A',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: 'aaa',
      );
      final b = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.systemEvent,
        summary: 'B',
        pinCode: '900002',
        occurredAt: DateTime.utc(2026, 8, 19, 10),
        prevHash: 'xxx',
        selfHash: 'yyy',
      );

      expect(a == b, true);
    });

    test('different seqs are not equal', () {
      final a = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.moderationAction,
        summary: 'A',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: 'aaa',
      );
      final b = TransparencyRecord(
        seq: 1,
        recordId: 'rec-001',
        action: TransparencyAction.moderationAction,
        summary: 'A',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: 'aaa',
        selfHash: 'bbb',
      );

      expect(a == b, false);
    });

    test('computeSelfHash produces deterministic result', () async {
      final record = TransparencyRecord(
        seq: 0,
        recordId: 'rec-001',
        action: TransparencyAction.moderationAction,
        summary: 'Test',
        pinCode: '800001',
        occurredAt: DateTime.utc(2026, 8, 18, 10),
        prevHash: TransparencyRecord.genesisHash,
        selfHash: '', // ignored by computation
      );

      final hash1 = await record.computeSelfHash(_FakeHasher());
      final hash2 = await record.computeSelfHash(_FakeHasher());
      expect(hash1, hash2);
      expect(hash1.length, 64); // 32 bytes = 64 hex chars
    });
  });
}

class _FakeHasher implements TransparencyHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    // Deterministic fake: hash = length mod 256 repeated 32 times.
    return Uint8List.fromList(List.generate(32, (i) => bytes.length % 256));
  }
}
