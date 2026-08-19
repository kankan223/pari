import 'dart:convert';
import 'dart:typed_data';

import 'audit_action.dart';

/// Port for SHA-256 hashing over canonical record bytes (Task 11.2).
///
/// Mirrors the hasher ports used by the transparency log (Task 10.5) and
/// the custody log (Task 8.6).
abstract class AuditHasher {
  /// SHA-256 hash of [bytes].
  Future<Uint8List> hash(List<int> bytes);
}

/// One append-only audit record (Task 11.2 Audit Logging System).
///
/// IMMUTABILITY + AUDIT (SECURITY CHECKPOINT 11.2): every record carries
/// [prevHash] (the [selfHash] of the previous record in the chain — a
/// 64-hex zero string for the first) and its own [selfHash] = SHA-256
/// over the record's canonical bytes. Any modification of a past record
/// breaks every subsequent link, so [AuditRepository.verifyIntegrity]
/// detects tampering by recomputing the chain.
///
/// SECURITY CHECKPOINT (11.2): records carry ONLY the fixed action label,
/// a public summary string (non-PII), and a timestamp. No names, no phone
/// numbers, no emails, no identity hashes.
class AuditRecord {
  /// Monotonic chain sequence (0-based).
  final int seq;

  /// UUID v4 identifier for this record.
  final String recordId;

  /// The fixed audit action.
  final AuditAction action;

  /// A short, public, non-PII summary of the action
  /// (e.g. "User granted consent for core functionality",
  /// "Data deletion requested").
  final String summary;

  /// Timestamp when the action occurred (UTC).
  final DateTime occurredAt;

  /// The SHA-256 hash of the previous record in the chain (64-hex lowercase).
  /// The genesis record uses the zero-hash.
  final String prevHash;

  /// The SHA-256 hash of this record's canonical bytes (64-hex lowercase).
  final String selfHash;

  const AuditRecord({
    required this.seq,
    required this.recordId,
    required this.action,
    required this.summary,
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
      'occurred_at': occurredAt.millisecondsSinceEpoch,
      'prev_hash': prevHash,
    };
    return utf8.encode(json.encode(map));
  }

  /// Computes the selfHash using the provided [hasher].
  Future<String> computeSelfHash(AuditHasher hasher) async {
    final digest = await hasher.hash(canonicalBytes);
    return digest.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuditRecord &&
          runtimeType == other.runtimeType &&
          seq == other.seq &&
          recordId == other.recordId;

  @override
  int get hashCode => seq.hashCode ^ recordId.hashCode;
}
