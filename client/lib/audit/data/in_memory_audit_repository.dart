import 'dart:typed_data';

import 'package:civic_commons/audit/domain/audit_record.dart';
import 'package:civic_commons/audit/domain/audit_repository.dart';

/// In-memory implementation of [AuditRepository] (Task 11.2).
///
/// Used in the testing harness and unit tests. Production persistence
/// backs onto the SQLCipher-encrypted database.
///
/// SECURITY CHECKPOINT (11.2): stores only [AuditRecord] objects
/// carrying public-label summaries — no identity, no PII, no tokens.
class InMemoryAuditRepository implements AuditRepository {
  final List<AuditRecord> _records = [];
  final AuditHasher _hasher;

  InMemoryAuditRepository({AuditHasher? hasher})
      : _hasher = hasher ?? const _NoopHasher();

  @override
  Future<List<AuditRecord>> getAll() async {
    return List<AuditRecord>.unmodifiable(_records);
  }

  @override
  Future<int> getCount() async => _records.length;

  @override
  Future<void> append(AuditRecord record) async {
    // Validate next-in-seq.
    final expectedSeq = _records.length;
    if (record.seq != expectedSeq) {
      throw StateError(
        'Expected seq $expectedSeq, got ${record.seq}',
      );
    }

    // Validate prevHash links to the chain.
    if (_records.isNotEmpty) {
      final last = _records.last;
      if (record.prevHash != last.selfHash) {
        throw StateError(
          'prevHash ${record.prevHash} does not match last selfHash ${last.selfHash}',
        );
      }
    } else if (record.prevHash != AuditRecord.genesisHash) {
      throw StateError(
        'Genesis record must have genesisHash prevHash, got ${record.prevHash}',
      );
    }

    _records.add(record);
  }

  @override
  Future<bool> verifyIntegrity() async {
    if (_records.isEmpty) return true;

    var expectedPrev = AuditRecord.genesisHash;
    for (var i = 0; i < _records.length; i++) {
      final record = _records[i];
      // Check seq is in order.
      if (record.seq != i) return false;
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
class _NoopHasher implements AuditHasher {
  const _NoopHasher();

  @override
  Future<Uint8List> hash(List<int> bytes) async {
    return Uint8List.fromList(List.generate(32, (i) => i % 256));
  }
}
