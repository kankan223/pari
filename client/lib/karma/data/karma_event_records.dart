import '../domain/karma_action.dart';
import '../domain/karma_event.dart';

/// Locally-persisted karma event row (Task 10.2).
///
/// Persisted inside the encrypted SQLCipher database (`karma_events`,
/// schema v14).
///
/// SECURITY CHECKPOINT (Task 10.2): the row carries ONLY the minted UUID
/// v4 event id, the monotonic sequence, the actor's validated 64-hex blind
/// hash, the fixed action wire code, the integer delta + running balance,
/// the timestamp, and the two 64-hex chain-link hashes — zero identity
/// columns, no names/phones/emails, no payload bytes.
class KarmaEventRecord {
  final String eventId;
  final int seq;
  final String actorHash;
  final KarmaAction action;
  final int delta;
  final int balanceAfter;
  final DateTime at;
  final String prevHash;
  final String selfHash;

  const KarmaEventRecord({
    required this.eventId,
    required this.seq,
    required this.actorHash,
    required this.action,
    required this.delta,
    required this.balanceAfter,
    required this.at,
    required this.prevHash,
    required this.selfHash,
  });

  KarmaEvent toEvent() => KarmaEvent(
        seq: seq,
        eventId: eventId,
        actorHash: actorHash,
        action: action,
        delta: delta,
        balanceAfter: balanceAfter,
        at: at,
        prevHash: prevHash,
        selfHash: selfHash,
      );

  /// Strict read-path revalidation (Task 10.2): a corrupt/forged row can
  /// never masquerade as a real event — the action must decode strictly and
  /// the delta must match the action's fixed value.
  static KarmaEventRecord? tryParse({
    required String eventId,
    required int seq,
    required String actorHash,
    required String action,
    required int delta,
    required int balanceAfter,
    required DateTime at,
    required String prevHash,
    required String selfHash,
  }) {
    final KarmaAction decoded;
    try {
      decoded = KarmaAction.fromWireName(action);
    } on ArgumentError {
      return null;
    }
    if (delta != decoded.delta) {
      return null; // delta must equal the action's fixed value.
    }
    if (!_is64Hex(actorHash) || !_is64Hex(prevHash) || !_is64Hex(selfHash)) {
      return null;
    }
    return KarmaEventRecord(
      eventId: eventId,
      seq: seq,
      actorHash: actorHash,
      action: decoded,
      delta: delta,
      balanceAfter: balanceAfter,
      at: at,
      prevHash: prevHash,
      selfHash: selfHash,
    );
  }

  static bool _is64Hex(String raw) =>
      raw.length == 64 && RegExp(r'^[0-9a-f]+$').hasMatch(raw);
}
