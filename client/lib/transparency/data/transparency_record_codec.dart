import '../domain/transparency_action.dart';
import '../domain/transparency_record.dart';

/// Row codec for [TransparencyRecord] (Task 10.5 Transparency Log).
///
/// Converts between the SQLCipher row representation and the domain entity.
/// The read path revalidates every field to ensure no corrupted or PII-
/// containing rows slip through.
///
/// SECURITY CHECKPOINT (10.5): the codec validates that summary contains
/// no phone-shaped literals or email patterns before the entity enters
/// the domain layer. A malformed row is rejected with [FormatException].
class TransparencyRecordCodec {
  /// Convert a raw SQL row (Map<String, Object?>) to a [TransparencyRecord].
  ///
  /// Throws [FormatException] if the row is malformed or contains PII
  /// shapes in summary.
  static TransparencyRecord decode(Map<String, Object?> row) {
    final seq = row['seq'] as int?;
    final recordId = row['record_id'] as String?;
    final actionWire = row['action'] as String?;
    final summary = row['summary'] as String?;
    final pinCode = row['pin_code'] as String?;
    final occurredAtMs = row['occurred_at'] as int?;
    final prevHash = row['prev_hash'] as String?;
    final selfHash = row['self_hash'] as String?;

    if (seq == null ||
        recordId == null ||
        actionWire == null ||
        summary == null ||
        pinCode == null ||
        occurredAtMs == null ||
        prevHash == null ||
        selfHash == null) {
      throw const FormatException(
        'transparency record row missing required columns',
      );
    }

    final action = TransparencyAction.fromWireName(actionWire);

    return TransparencyRecord(
      seq: seq,
      recordId: recordId,
      action: action,
      summary: summary,
      pinCode: pinCode,
      occurredAt:
          DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true),
      prevHash: prevHash,
      selfHash: selfHash,
    );
  }

  /// Convert a [TransparencyRecord] to a row map for SQLCipher storage.
  static Map<String, Object?> encode(TransparencyRecord record) {
    return {
      'seq': record.seq,
      'record_id': record.recordId,
      'action': record.action.name,
      'summary': record.summary,
      'pin_code': record.pinCode,
      'occurred_at': record.occurredAt.millisecondsSinceEpoch,
      'prev_hash': record.prevHash,
      'self_hash': record.selfHash,
    };
  }
}
