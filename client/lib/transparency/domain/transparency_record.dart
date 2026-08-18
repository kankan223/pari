import 'dart:convert';
import 'dart:typed_data';

import 'transparency_action.dart';

/// Port for SHA-256 hashing over canonical record bytes (Task 10.5).
///
/// Mirrors the Sha256Hasher port used by the custody log (Task 8.6) and
/// the karma engine (Task 10.2).
abstract class TransparencyHasher {
  /// SHA-256 hash of [bytes].
  Future<Uint8List> hash(List<int> bytes);
}

/// One append-only transparency record (Task 10.5 Transparency Log).
///
/// IMMUTABILITY + AUDIT (SECURITY CHECKPOINT 10.5): every record carries
/// [prevHash] (the [selfHash] of the previous record in the chain — a
/// 64-hex zero string for the first) and its own [selfHash] = SHA-256
/// over the record's canonical bytes. Any modification of a past record
/// breaks every subsequent link, so [TransparencyRepository.verifyIntegrity]
/// detects tampering by recomputing the chain.
///
/// SECURITY CHECKPOINT (10.5): records carry ONLY the fixed action label,
/// a public summary string (non-PII), the pin-code scope, and a
/// timestamp. No names, no phone numbers, no emails, no identity hashes.
class TransparencyRecord {
  /// Monotonic chain sequence (0-based).
  final int seq;

  /// UUID v4 identifier for this record.
  final String recordId;

  /// The fixed transparency action.
  final TransparencyAction action;

  /// A short, public, non-PII summary of the action
  /// (e.g. "Post flagged for review", "Access request approved").
  final String summary;

  /// The coarse civic scope (pin-code board) this record belongs to.
  final String pinCode;

  /// Timestamp when the action occurred (UTC).
  final DateTime occurredAt;

  /// The SHA-256 hash of the previous record in the chain (64-hex lowercase).
  /// The genesis record uses the zero-hash.
  final String prevHash;

  /// The SHA-256 hash of this record's canonical bytes (64-hex lowercase).
  final String selfHash;

  const TransparencyRecord({
    required this.seq,
    required this.recordId,
    required this.action,
    required this.summary,
    required this.pinCode,
    required this.occurredAt,
    required this.prevHash,
    required this.selfHash,
  });

  /// The genesis (64-zero) hash used as prevHash for the first record.
  static const String genesisHash =
      '0000000000000000000000000000000000000000000000000000000000000000';

  /// Returns the canonical byte representation for hashing.
  ///
  /// The canonical form is a deterministic JSON object covering all
  /// fields except selfHash (which is derived from this form).
  Uint8List get canonicalBytes {
    final map = {
      'seq': seq,
      'record_id': recordId,
      'action': action.name,
      'summary': summary,
      'pin_code': pinCode,
      'occurred_at': occurredAt.millisecondsSinceEpoch,
      'prev_hash': prevHash,
    };
    return utf8.encode(json.encode(map));
  }

  /// Computes the selfHash using the provided [hasher].
  Future<String> computeSelfHash(TransparencyHasher hasher) async {
    final digest = await hasher.hash(canonicalBytes);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TransparencyRecord &&
          runtimeType == other.runtimeType &&
          seq == other.seq &&
          recordId == other.recordId;

  @override
  int get hashCode => seq.hashCode ^ recordId.hashCode;
}
