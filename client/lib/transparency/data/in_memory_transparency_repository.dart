import 'dart:typed_data';

import 'package:civic_commons/transparency/domain/transparency_record.dart';
import 'package:civic_commons/transparency/domain/transparency_repository.dart';

/// In-memory implementation of [TransparencyRepository] (Task 10.5).
///
/// Used in the testing harness and unit tests. Production persistence
/// backs onto the SQLCipher-encrypted database (deferred to Phase 9
/// integration).
///
/// SECURITY CHECKPOINT (10.5): stores only [TransparencyRecord] objects
/// carrying public-label summaries — no identity, no PII, no tokens.
class InMemoryTransparencyRepository implements TransparencyRepository {
  final Map<String, List<TransparencyRecord>> _recordsByPin = {};
  final TransparencyHasher _hasher;

  InMemoryTransparencyRepository({TransparencyHasher? hasher})
      : _hasher = hasher ?? const _NoopHasher();

  @override
  Future<List<TransparencyRecord>> getByPinCode(String pinCode) async {
    final records = _recordsByPin[pinCode] ?? [];
    return List<TransparencyRecord>.unmodifiable(records);
  }

  @override
  Future<int> getCount(String pinCode) async {
    return (_recordsByPin[pinCode] ?? []).length;
  }

  @override
  Future<void> append(TransparencyRecord record) async {
    final pinCode = record.pinCode;
    final existing = _recordsByPin[pinCode] ?? [];

    // Validate next-in-seq.
    final expectedSeq = existing.length;
    if (record.seq != expectedSeq) {
      throw StateError(
        'Expected seq $expectedSeq for $pinCode, got ${record.seq}',
      );
    }

    // Validate prevHash links to the chain.
    if (existing.isNotEmpty) {
      final last = existing.last;
      if (record.prevHash != last.selfHash) {
        throw StateError(
          'prevHash ${record.prevHash} does not match last selfHash ${last.selfHash}',
        );
      }
    } else if (record.prevHash != TransparencyRecord.genesisHash) {
      throw StateError(
        'Genesis record must have genesisHash prevHash, got ${record.prevHash}',
      );
    }

    existing.add(record);
    _recordsByPin[pinCode] = existing;
  }

  @override
  Future<bool> verifyIntegrity(String pinCode) async {
    final records = _recordsByPin[pinCode] ?? [];
    if (records.isEmpty) return true;

    var expectedPrev = TransparencyRecord.genesisHash;
    for (final record in records) {
      // Check seq is in order.
      if (record.seq != records.indexOf(record)) return false;
      // Check prevHash links.
      if (record.prevHash != expectedPrev) return false;
      // Recompute selfHash.
      final recomputed = await record.computeSelfHash(_hasher);
      if (recomputed != record.selfHash) return false;
      expectedPrev = record.selfHash;
    }
    return true;
  }
}

/// A no-op hasher for tests that don't verify hash chains.
class _NoopHasher implements TransparencyHasher {
  const _NoopHasher();

  @override
  Future<Uint8List> hash(List<int> bytes) async {
    // Return a deterministic fake hash based on the byte length.
    // This is NOT cryptographically secure — only used for unit tests
    // that don't verify chain integrity.
    return Uint8List.fromList(List.generate(32, (i) => i % 256));
  }
}
