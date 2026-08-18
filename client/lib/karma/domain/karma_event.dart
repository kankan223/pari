import 'dart:convert';
import 'dart:typed_data';

import 'karma_action.dart';

/// Port for SHA-256 hashing over canonical event bytes (Task 10.2).
abstract class Sha256Hasher {
  /// SHA-256 hash of [bytes].
  Future<Uint8List> hash(List<int> bytes);
}

/// One append-only karma event (Task 10.2 — Civic Karma Engine).
///
/// IMMUTABILITY + AUDIT (SECURITY CHECKPOINT 10.2): every event carries
/// [prevHash] (the [selfHash] of the previous event in the chain — a
/// 64-hex zero string for the first) and its own [selfHash] = SHA-256 over
/// the event's canonical bytes. Any modification of a past event breaks
/// every subsequent link, so [KarmaRepository.verifyIntegrity] detects
/// tampering by recomputing the chain. The karma ledger is APPEND-ONLY —
/// there is no update or delete API; only the sequence-validated append.
///
/// SECURITY CHECKPOINT (10.2): events carry ONLY the action's wire code +
/// pillar + delta, the actor's validated 64-hex BLIND hash, the running
/// balance, and a timestamp. No names, no phones, no emails, no payload
/// bytes — the blind hash is the only actor identifier and it is never
/// rendered anywhere.
class KarmaEvent {
  /// Monotonic chain sequence (0-based).
  final int seq;

  /// Minted UUID v4 event id (the wire `Idempotency-Key` for replay dedup).
  final String eventId;

  /// The actor's validated 64-hex blind hash. NEVER rendered.
  final String actorHash;

  final KarmaAction action;

  /// Fixed action delta (already applied to [balanceAfter]).
  final int delta;

  /// The running karma balance AFTER this event (start: 0).
  final int balanceAfter;

  final DateTime at;

  /// selfHash of the previous event in the chain (64-hex zeros for seq 0).
  final String prevHash;

  /// SHA-256 over this event's canonical bytes (64 hex chars).
  final String selfHash;

  const KarmaEvent({
    required this.seq,
    required this.eventId,
    required this.actorHash,
    required this.action,
    required this.delta,
    required this.balanceAfter,
    required this.at,
    required this.prevHash,
    required this.selfHash,
  });

  /// The canonical byte stream that [selfHash] covers — deterministic and
  /// stable across devices, so every peer recomputes identical hashes.
  Uint8List canonicalBytes() => Uint8List.fromList(utf8.encode([
        'karma_event',
        seq.toString(),
        eventId,
        actorHash,
        action.wireName,
        delta.toString(),
        balanceAfter.toString(),
        at.toUtc().microsecondsSinceEpoch.toString(),
        prevHash,
      ].join('|')));

  /// Recomputes this event's selfHash over its canonical bytes with
  /// [hasher] (used by [KarmaRepository.verifyIntegrity]).
  Future<String> recomputeSelfHash(Sha256Hasher hasher) async {
    final bytes = await hasher.hash(canonicalBytes());
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}
