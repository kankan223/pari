import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../repository/domain/entity_store.dart';
import '../../repository/domain/idempotency_key.dart';
import '../domain/karma_action.dart';
import '../domain/karma_event.dart';
import '../domain/karma_repository.dart';
import 'karma_event_records.dart';

/// Real SHA-256 hasher over the `cryptography` package (Task 10.2).
class RealKarmaSha256Hasher implements Sha256Hasher {
  const RealKarmaSha256Hasher();

  @override
  Future<Uint8List> hash(List<int> bytes) async =>
      Uint8List.fromList((await Sha256().hash(bytes)).bytes);
}

/// Production [KarmaRepository] (Task 10.2 — Civic Karma Engine).
///
/// Persists the append-only karma ledger inside the encrypted SQLCipher
/// database (`karma_events`, schema v14). OFFLINE-FIRST: every karma event
/// lands in the encrypted partition immediately; the balance is ALWAYS a
/// deterministic projection of the chain, never a separately-mutated
/// counter, so the ledger stays auditable end-to-end.
///
/// SECURITY CHECKPOINT (10.2): APPEND-ONLY — there is no update/delete API;
/// [record] enforces the chain invariants (exactly-next sequence + prevHash
/// link) or throws; [verifyIntegrity] walks the chain and recomputes every
/// selfHash over the event's canonical bytes, so any tampering (edited
/// actor/action/delta/balance/timestamp, inserted or reordered event) is
/// detected. The actor is a validated 64-hex blind hash — zero PII.
class LocalKarmaRepository implements KarmaRepository {
  final EntityStore<KarmaEventRecord> _store;
  final IdempotencyKeyGenerator _idGen;
  final Sha256Hasher _hasher;
  final DateTime Function() _clock;

  /// The 64-hex zero prevHash for the first event of the chain.
  static final String zeroHash = List.filled(64, '0').join();

  static final RegExp _hash64 = RegExp(r'^[0-9a-f]{64}$');

  LocalKarmaRepository({
    required EntityStore<KarmaEventRecord> store,
    IdempotencyKeyGenerator? idempotencyKeys,
    Sha256Hasher? hasher,
    DateTime Function()? clock,
  })  : _store = store,
        _idGen = idempotencyKeys ?? IdempotencyKeyGenerator(),
        _hasher = hasher ?? const RealKarmaSha256Hasher(),
        _clock = clock ?? DateTime.now;

  Future<String> _hexHash(List<int> input) async => (await _hasher.hash(input))
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join();

  @override
  Future<int> balance() async {
    final events = await _sortedEvents();
    return events.isEmpty ? 0 : events.last.balanceAfter;
  }

  @override
  Future<List<KarmaEvent>> events() async =>
      (await _sortedEvents()).map((r) => r.toEvent()).toList(growable: false);

  Future<List<KarmaEventRecord>> _sortedEvents() async {
    final all = [...await _store.getAll()]
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return all;
  }

  @override
  Future<KarmaEvent> record({
    required KarmaAction action,
    required String actorHash,
    DateTime? at,
  }) async {
    final hash = actorHash.trim().toLowerCase();
    if (!_hash64.hasMatch(hash)) {
      throw ArgumentError('actorHash must be a 64-hex blind hash');
    }
    final now = at ?? _clock();
    final chain = await _sortedEvents();
    final seq = chain.length;
    final prevHash = chain.isEmpty ? zeroHash : chain.last.selfHash;
    final balanceAfter =
        (chain.isEmpty ? 0 : chain.last.balanceAfter) + action.delta;

    final event = KarmaEvent(
      seq: seq,
      eventId: _idGen.generate(),
      actorHash: hash,
      action: action,
      delta: action.delta,
      balanceAfter: balanceAfter,
      at: now,
      prevHash: prevHash,
      selfHash: '',
    );
    // selfHash covers the canonical bytes INCLUDING prevHash — a chain link.
    final selfHash = await _hexHash(event.canonicalBytes());
    final finalized = KarmaEvent(
      seq: event.seq,
      eventId: event.eventId,
      actorHash: event.actorHash,
      action: event.action,
      delta: event.delta,
      balanceAfter: event.balanceAfter,
      at: event.at,
      prevHash: event.prevHash,
      selfHash: selfHash,
    );

    await _store.insert(KarmaEventRecord(
      eventId: finalized.eventId,
      seq: finalized.seq,
      actorHash: finalized.actorHash,
      action: finalized.action,
      delta: finalized.delta,
      balanceAfter: finalized.balanceAfter,
      at: finalized.at,
      prevHash: finalized.prevHash,
      selfHash: finalized.selfHash,
    ));
    return finalized;
  }

  @override
  Future<bool> verifyIntegrity() async {
    final chain = await _sortedEvents();
    var expectedPrev = zeroHash;
    for (var i = 0; i < chain.length; i++) {
      final record = chain[i];
      if (record.seq != i) {
        return false; // gap, duplicate, or reorder.
      }
      if (record.prevHash != expectedPrev) {
        return false; // broken link.
      }
      final recomputed = await _hexHash(record.toEvent().canonicalBytes());
      if (recomputed != record.selfHash) {
        return false; // event bytes were modified.
      }
      expectedPrev = record.selfHash;
    }
    return true;
  }
}
