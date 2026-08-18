import 'dart:typed_data';

import 'package:civic_commons/transparency/data/in_memory_transparency_repository.dart';
import 'package:civic_commons/transparency/domain/transparency_action.dart';
import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:civic_commons/transparency/domain/transparency_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryTransparencyRepository repo;

  setUp(() {
    repo = InMemoryTransparencyRepository(hasher: _DeterministicHasher());
  });

  group('append', () {
    test('accepts genesis record with correct prevHash', () async {
      final record = await _makeRecord(
        seq: 0,
        summary: 'System initialized',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(record);

      final records = await repo.getByPinCode('800001');
      expect(records.length, 1);
    });

    test('rejects record with wrong prevHash', () async {
      final record = await _makeRecord(
        seq: 0,
        summary: 'System initialized',
        prevHash: 'wrong_hash',
      );
      expect(() => repo.append(record), throwsStateError);
    });

    test('rejects record with non-sequential seq', () async {
      final record = await _makeRecord(
        seq: 5,
        summary: 'Out of order',
        prevHash: TransparencyRecord.genesisHash,
      );
      expect(() => repo.append(record), throwsStateError);
    });

    test('chains records correctly', () async {
      final r0 = await _makeRecord(
        seq: 0,
        summary: 'First',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);

      final r1 = await _makeRecord(
        seq: 1,
        summary: 'Second',
        prevHash: r0.selfHash,
      );
      await repo.append(r1);

      final records = await repo.getByPinCode('800001');
      expect(records.length, 2);
      expect(records[0].summary, 'First');
      expect(records[1].summary, 'Second');
      expect(records[1].prevHash, r0.selfHash);
    });
  });

  group('getByPinCode', () {
    test('returns empty list for unknown pinCode', () async {
      final records = await repo.getByPinCode('000000');
      expect(records, isEmpty);
    });

    test('isolates records by pinCode', () async {
      final r0 = await _makeRecord(
        seq: 0,
        summary: 'Pin A',
        pinCode: '111111',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);

      final records = await repo.getByPinCode('222222');
      expect(records, isEmpty);
    });
  });

  group('getCount', () {
    test('returns 0 for unknown pinCode', () async {
      expect(await repo.getCount('000000'), 0);
    });

    test('returns correct count', () async {
      final r0 = await _makeRecord(
        seq: 0,
        summary: 'First',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);
      expect(await repo.getCount('800001'), 1);
    });
  });

  group('verifyIntegrity', () {
    test('returns true for empty log', () async {
      expect(await repo.verifyIntegrity('800001'), true);
    });

    test('returns true for valid chain', () async {
      final r0 = await _makeRecord(
        seq: 0,
        summary: 'First',
        prevHash: TransparencyRecord.genesisHash,
      );
      await repo.append(r0);

      final r1 = await _makeRecord(
        seq: 1,
        summary: 'Second',
        prevHash: r0.selfHash,
      );
      await repo.append(r1);

      expect(await repo.verifyIntegrity('800001'), true);
    });

    test('detects tampered selfHash', () async {
      // Use a repo that stores tampered records.
      final tamperRepo = _TamperingTransparencyRepository(
        hasher: _DeterministicHasher(),
      );

      final r0 = await _makeRecord(
        seq: 0,
        summary: 'First',
        prevHash: TransparencyRecord.genesisHash,
      );
      await tamperRepo.append(r0);

      // The tamper repo replaces selfHash with 'TAMPERED'.
      expect(await tamperRepo.verifyIntegrity('800001'), false);
    });
  });
}

/// Helper to create a test record with pre-computed selfHash.
Future<TransparencyRecord> _makeRecord({
  required int seq,
  required String summary,
  String? pinCode,
  required String prevHash,
}) async {
  final hasher = _DeterministicHasher();
  final record = TransparencyRecord(
    seq: seq,
    recordId: 'rec-${seq.toString().padLeft(3, '0')}',
    action: TransparencyAction.systemEvent,
    summary: summary,
    pinCode: pinCode ?? '800001',
    occurredAt: DateTime.utc(2026, 8, 18, 10 + seq),
    prevHash: prevHash,
    selfHash: '', // will be computed
  );
  final selfHash = await record.computeSelfHash(hasher);
  return TransparencyRecord(
    seq: record.seq,
    recordId: record.recordId,
    action: record.action,
    summary: record.summary,
    pinCode: record.pinCode,
    occurredAt: record.occurredAt,
    prevHash: record.prevHash,
    selfHash: selfHash,
  );
}

/// A deterministic hasher that produces the same hash for the same input.
class _DeterministicHasher implements TransparencyHasher {
  @override
  Future<Uint8List> hash(List<int> bytes) async {
    // Simple deterministic hash: XOR all bytes into 32 slots.
    final result = Uint8List(32);
    for (var i = 0; i < bytes.length; i++) {
      result[i % 32] ^= bytes[i];
    }
    return result;
  }
}

/// A repository that tampers with selfHash on append (for testing integrity).
class _TamperingTransparencyRepository implements TransparencyRepository {
  final Map<String, List<TransparencyRecord>> _recordsByPin = {};
  final TransparencyHasher _hasher;

  _TamperingTransparencyRepository({TransparencyHasher? hasher})
      : _hasher = hasher ?? _DeterministicHasher();

  @override
  Future<List<TransparencyRecord>> getByPinCode(String pinCode) async {
    return List<TransparencyRecord>.unmodifiable(
        _recordsByPin[pinCode] ?? []);
  }

  @override
  Future<int> getCount(String pinCode) async {
    return (_recordsByPin[pinCode] ?? []).length;
  }

  @override
  Future<void> append(TransparencyRecord record) async {
    final pinCode = record.pinCode;
    final existing = _recordsByPin[pinCode] ?? [];
    // Tamper: replace selfHash with a known-bad value.
    existing.add(TransparencyRecord(
      seq: record.seq,
      recordId: record.recordId,
      action: record.action,
      summary: record.summary,
      pinCode: record.pinCode,
      occurredAt: record.occurredAt,
      prevHash: record.prevHash,
      selfHash: 'TAMPERED',
    ));
    _recordsByPin[pinCode] = existing;
  }

  @override
  Future<bool> verifyIntegrity(String pinCode) async {
    final records = _recordsByPin[pinCode] ?? [];
    if (records.isEmpty) return true;

    var expectedPrev = TransparencyRecord.genesisHash;
    for (final record in records) {
      if (record.seq != records.indexOf(record)) return false;
      if (record.prevHash != expectedPrev) return false;
      final recomputed = await record.computeSelfHash(_hasher);
      if (recomputed != record.selfHash) return false;
      expectedPrev = record.selfHash;
    }
    return true;
  }
}
