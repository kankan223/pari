import 'package:civic_commons/consent/domain/consent_record.dart';
import 'package:civic_commons/consent/domain/consent_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConsentRecord', () {
    test('constructs with required fields', () {
      final record = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 10),
        textHash: 'abc123',
      );

      expect(record.recordId, 'consent-001');
      expect(record.type, ConsentType.coreFunctionality);
      expect(record.granted, true);
    });

    test('withdraw returns a copy with granted=false', () {
      final record = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.civicEngagement,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 10),
        textHash: 'abc123',
      );

      final withdrawn = record.withdraw();
      expect(withdrawn.granted, false);
      expect(withdrawn.type, record.type);
      expect(withdrawn.consentVersion, record.consentVersion);
    });

    test('original is unchanged after withdraw', () {
      final record = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.securityContributions,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 10),
        textHash: 'abc123',
      );

      record.withdraw();
      expect(record.granted, true);
    });

    test('equality is based on recordId and granted', () {
      final a = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 10),
        textHash: 'abc',
      );
      final b = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.civicEngagement,
        consentVersion: '2.0',
        granted: false,
        timestamp: DateTime.utc(2026, 8, 19, 10),
        textHash: 'def',
      );

      // Same id but different granted → not equal
      expect(a == b, false);
    });

    test('same id and granted are equal', () {
      final a = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.coreFunctionality,
        consentVersion: '1.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 18, 10),
        textHash: 'abc',
      );
      final b = ConsentRecord(
        recordId: 'consent-001',
        type: ConsentType.analytics,
        consentVersion: '3.0',
        granted: true,
        timestamp: DateTime.utc(2026, 8, 19, 10),
        textHash: 'xyz',
      );

      expect(a == b, true);
    });
  });
}
