import '../domain/consent_record.dart';
import '../domain/consent_type.dart';

/// Row codec for [ConsentRecord] (Task 11.1 DPDP Consent).
///
/// Converts between the SQLCipher row representation and the domain entity.
/// The read path revalidates every field to ensure no corrupted or PII-
/// containing rows slip through.
///
/// SECURITY CHECKPOINT (11.1): the codec validates that the consent type
/// is a known wire code before the entity enters the domain layer. A
/// malformed row is rejected with [FormatException].
class ConsentRecordCodec {
  /// Convert a raw SQL row (Map<String, Object?>) to a [ConsentRecord].
  ///
  /// Throws [FormatException] if the row is malformed.
  static ConsentRecord decode(Map<String, Object?> row) {
    final recordId = row['record_id'] as String?;
    final typeWire = row['type'] as String?;
    final consentVersion = row['consent_version'] as String?;
    final granted = row['granted'] as int?;
    final timestampMs = row['timestamp'] as int?;
    final textHash = row['text_hash'] as String?;

    if (recordId == null ||
        typeWire == null ||
        consentVersion == null ||
        granted == null ||
        timestampMs == null ||
        textHash == null) {
      throw const FormatException(
          'consent record row missing required columns');
    }

    final type = ConsentType.fromWireName(typeWire);

    return ConsentRecord(
      recordId: recordId,
      type: type,
      consentVersion: consentVersion,
      granted: granted == 1,
      timestamp: DateTime.fromMillisecondsSinceEpoch(timestampMs, isUtc: true),
      textHash: textHash,
    );
  }

  /// Convert a [ConsentRecord] to a row map for SQLCipher storage.
  static Map<String, Object?> encode(ConsentRecord record) {
    return {
      'record_id': record.recordId,
      'type': record.type.wireName,
      'consent_version': record.consentVersion,
      'granted': record.granted ? 1 : 0,
      'timestamp': record.timestamp.millisecondsSinceEpoch,
      'text_hash': record.textHash,
    };
  }
}
