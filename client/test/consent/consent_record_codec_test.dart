import 'package:civic_commons/consent/data/consent_record_codec.dart';
import 'package:civic_commons/consent/domain/consent_record.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsentRecordCodec', () {
    test('encode produces correct map', () {
      final record = ConsentRecord(
        recordId: 'r1',
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 12),
        textHash: 'hash_abc',
      );

      final row = ConsentRecordCodec.encode(record);
      expect(row['record_id'], 'r1');
      expect(row['type'], 'core_functionality');
      expect(row['consent_version'], '1.0');
      expect(row['granted'], 1);
      expect(row['timestamp'],
          DateTime.utc(2026, 8, 18, 12).millisecondsSinceEpoch);
      expect(row['text_hash'], 'hash_abc');
    });

    test('decode round-trips correctly', () {
      final original = ConsentRecord(
        recordId: 'r2',
        type: ConsentType.civicEngagement,
        consentVersion: '2.0',
        granted: false,
        timestamp: DateTime.utc(2026, 8, 19, 10),
        textHash: 'hash_def',
      );

      final row = ConsentRecordCodec.encode(original);
      final decoded = ConsentRecordCodec.decode(row);

      expect(decoded.recordId, original.recordId);
      expect(decoded.type, original.type);
      expect(decoded.consentVersion, original.consentVersion);
      expect(decoded.granted, original.granted);
      expect(decoded.timestamp, original.timestamp);
      expect(decoded.textHash, original.textHash);
    });

    test('decode encodes granted=0 as false', () {
      final row = {
        'record_id': 'r3',
        'type': 'analytics',
        'consent_version': '1.0',
        'granted': 0,
        'timestamp': 1723994400000,
        'text_hash': 'hash_xyz',
      };

      final decoded = ConsentRecordCodec.decode(row);
      expect(decoded.granted, false);
    });

    test('decode throws FormatException for missing columns', () {
      expect(
        () => ConsentRecordCodec.decode({'record_id': 'r1'}),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for unknown type', () {
      final row = {
        'record_id': 'r1',
        'type': 'unknown_type',
        'consent_version': '1.0',
        'granted': 1,
        'timestamp': 1723994400000,
        'text_hash': 'h',
      };

      expect(
        () => ConsentRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('decode throws FormatException for null values', () {
      final row = {
        'record_id': null,
        'type': 'core_functionality',
        'consent_version': '1.0',
        'granted': 1,
        'timestamp': 1723994400000,
        'text_hash': 'h',
      };

      expect(
        () => ConsentRecordCodec.decode(row),
        throwsFormatException,
      );
    });

    test('round-trip for all consent types', () {
      for (final type in ConsentType.values) {
        final record = ConsentRecord(
          recordId: 'r-${type.wireName}',
          type: type,
          consentVersion: '1.0',
          granted: true,
          timestamp: DateTime.utc(2026, 8, 18),
          textHash: 'h',
        );

        final row = ConsentRecordCodec.encode(record);
        final decoded = ConsentRecordCodec.decode(row);
        expect(decoded.type, type);
      }
    });
  });
}
