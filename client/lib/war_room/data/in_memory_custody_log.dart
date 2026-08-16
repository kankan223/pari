import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/custody_log.dart';

/// Real SHA-256 hasher over the `cryptography` package (Task 8.6).
class RealSha256Hasher implements Sha256Hasher {
  const RealSha256Hasher();

  @override
  Future<Uint8List> hash(List<int> bytes) async =>
      Uint8List.fromList((await Sha256().hash(bytes)).bytes);
}

/// In-memory, LOCAL-FIRST append-only [CustodyLog] (Task 8.6).
///
/// The log is APPEND-ONLY: [append] is the only mutation path and it enforces
/// the chain invariants (next sequence + prevHash link) or throws. There is
/// NO update, delete, or reorder API — the hash chain makes any out-of-band
/// modification detectable via [verifyIntegrity].
///
/// SECURITY CHECKPOINT (8.6): each event's [CustodyEvent.selfHash] is the
/// SHA-256 of its canonical bytes; every event carries the previous event's
/// hash. [verifyIntegrity] walks each case's chain from seq 0 and recomputes
/// every hash from the stored fields — any tampering (edited actor/label/
/// timestamp, inserted or reordered event) breaks the recomputation and
/// reports false. No encryption/decryption is ever performed here.
class InMemoryCustodyLog implements CustodyLog {
  final Map<String, List<CustodyEvent>> _events = {};
  final Sha256Hasher _hasher;

  /// The 64-hex zero prevHash for the first event of every chain.
  static final String zeroHash = List.filled(64, '0').join();

  InMemoryCustodyLog({Sha256Hasher? hasher})
      : _hasher = hasher ?? const RealSha256Hasher();

  /// Computes the 64-hex SHA-256 of [input].
  Future<String> _hexHash(List<int> input) async => (await _hasher.hash(input))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  @override
  Future<CustodyEvent> buildEvent({
    required String caseNumber,
    required CustodyEventType type,
    required String actor,
    required DateTime at,
  }) async {
    final chain = _events[caseNumber] ?? const [];
    final seq = chain.length;
    final prevHash = chain.isEmpty ? zeroHash : chain.last.selfHash;
    // selfHash covers the canonical bytes INCLUDING prevHash — a chain link.
    final selfHash = await _hexHash(
      '$seq|$caseNumber|${type.name}|$actor|${at.microsecondsSinceEpoch}|$prevHash'
          .codeUnits,
    );
    return CustodyEvent(
      seq: seq,
      caseNumber: caseNumber,
      type: type,
      actor: actor,
      at: at,
      prevHash: prevHash,
      selfHash: selfHash,
    );
  }

  @override
  Future<void> append(CustodyEvent event) async {
    final chain = _events[event.caseNumber] ?? const <CustodyEvent>[];
    // Enforce the append-only chain invariants: exactly-next sequence and a
    // valid prevHash link (zeros for the first, the tail's selfHash after).
    final expectedPrev = chain.isEmpty ? zeroHash : chain.last.selfHash;
    if (event.seq != chain.length) {
      throw StateError(
          'append-only violation: expected seq ${chain.length}, got ${event.seq}');
    }
    if (event.prevHash != expectedPrev) {
      throw StateError(
          'append-only violation: prevHash does not link to the chain tail');
    }
    _events[event.caseNumber] = [...chain, event];
  }

  @override
  Future<List<CustodyEvent>> entries(String caseNumber) async =>
      List.unmodifiable(_events[caseNumber] ?? const <CustodyEvent>[]);

  @override
  Future<CustodyEvent?> lastEvent(String caseNumber) async {
    final chain = _events[caseNumber];
    return chain == null || chain.isEmpty ? null : chain.last;
  }

  @override
  Future<bool> verifyIntegrity() async {
    for (final entry in _events.entries) {
      final chain = entry.value;
      for (var i = 0; i < chain.length; i++) {
        final event = chain[i];
        if (event.seq != i) {
          return false;
        }
        final expectedPrev = i == 0 ? zeroHash : chain[i - 1].selfHash;
        if (event.prevHash != expectedPrev) {
          return false;
        } // Recompute the selfHash from the stored FIELDS — if anyone edited
        // actor/label/timestamp, the recomputation disagrees with the
        // stored hash and the chain is broken.
        final recomputed = await _hexHash(
          '${event.seq}|${event.caseNumber}|${event.type.name}|${event.actor}'
                  '|${event.at.microsecondsSinceEpoch}|${event.prevHash}'
              .codeUnits,
        );
        if (recomputed != event.selfHash) {
          return false;
        }
      }
    }
    return true;
  }

  /// TEST-ONLY hook: replaces the event at [index] of [caseNumber] with
  /// [forged] to prove [verifyIntegrity] detects out-of-band tampering.
  /// Never used in production code paths — the append-only contract is
  /// enforced on every real mutation path.
  void tamperForTest(String caseNumber, int index, CustodyEvent forged) {
    final chain = _events[caseNumber]!;
    final copy = [...chain];
    copy[index] = forged;
    _events[caseNumber] = copy;
  }
}
