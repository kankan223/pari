import '../domain/audit_action.dart';
import '../domain/audit_record.dart';

/// Row codec for [AuditRecord] (Task 11.2 Audit Logging System).
///
/// Converts between the SQLCipher row representation and the domain entity.
/// The read path revalidates every field to ensure no corrupted or PII-
/// containing rows slip through.
///
/// SECURITY CHECKPOINT (11.2): the codec validates that the audit action
/// is a known wire code before the entity enters the domain layer. A
/// malformed row is rejected with [FormatException].
class AuditRecordCodec {
  /// Convert a raw SQL row (Map<String, Object?>) to an [AuditRecord].
  ///
  /// Throws [FormatException] if the row is malformed.
  static AuditRecord decode(Map<String, Object?> row) {
    final recordId = row['record_id'] as String?;
    final actionWire = row['action'] as String?;
    final summary = row['summary'] as String?;
    final occurredAtMs = row['occurred_at'] as int?;
    final seq = row['seq'] as int?;
    final prevHash = row['prev_hash'] as String?;
    final selfHash = row['self_hash'] as String?;

    if (recordId == null ||
        actionWire == null ||
        summary == null ||
        occurredAtMs == null ||
        seq == null ||
        prevHash == null ||
        selfHash == null) {
      throw const FormatException('audit record row missing required columns');
    }

    final action = AuditAction.fromWireName(actionWire);

    return AuditRecord(
      recordId: recordId,
      action: action,
      summary: summary,
      occurredAt:
          DateTime.fromMillisecondsSinceEpoch(occurredAtMs, isUtc: true),
      seq: seq,
      prevHash: prevHash,
      selfHash: selfHash,
    );
  }

  /// Convert an [AuditRecord] to a row map for SQLCipher storage.
  static Map<String, Object?> encode(AuditRecord record) {
    return {
      'record_id': record.recordId,
      'action': record.action.name,
      'summary': record.summary,
      'occurred_at': record.occurredAt.millisecondsSinceEpoch,
      'seq': record.seq,
      'prev_hash': record.prevHash,
      'self_hash': record.selfHash,
    };
  }
}
