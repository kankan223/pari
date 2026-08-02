import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/logging/data/default_pii_redactor.dart';

void main() {
  const redactor = DefaultPiiRedactor();

  group('DefaultPiiRedactor - PII redaction', () {
    test('redacts E.164 phone numbers', () {
      final out = redactor.redact('Contact +14155552671 for details');

      expect(out, isNot(contains('+14155552671')));
      expect(out, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts email addresses', () {
      final out = redactor.redact('Email user@example.com to proceed');

      expect(out, isNot(contains('user@example.com')));
      expect(out, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts US social security numbers', () {
      final out = redactor.redact('SSN 123-45-6789 on file');

      expect(out, isNot(contains('123-45-6789')));
      expect(out, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts credit card numbers', () {
      final out = redactor.redact('Card 4111 1111 1111 1111 charged');

      expect(out, isNot(contains('4111 1111 1111 1111')));
      expect(out, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts long hex tokens (blind-hash IDs, API keys)', () {
      final out = redactor.redact('token=5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2');

      expect(
        out,
        isNot(contains('5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2')),
      );
    });

    test('redacts bearer tokens', () {
      final out = redactor.redact('Authorization: Bearer eyJhbGciOiJIUzI1NiJ9.abc.def');

      expect(out, isNot(contains('eyJhbGciOiJIUzI1NiJ9.abc.def')));
    });

    test('redacts key=value secrets (api_key, password, etc.)', () {
      final out = redactor.redact('api_key=sk-12345abcdef stored');

      expect(out, isNot(contains('sk-12345abcdef')));
    });

    test('leaves benign text untouched', () {
      const benign = 'User logged in successfully';
      expect(redactor.redact(benign), equals(benign));
    });

    test('redacts domestic phone numbers with separators', () {
      final out = redactor.redact('Call 555-123-4567 today');

      expect(out, isNot(contains('555-123-4567')));
      expect(out, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts domestic phone numbers without separators', () {
      final out = redactor.redact('Call 5551234567 today');

      expect(out, isNot(contains('5551234567')));
    });

    test('does NOT redact ISO dates (log timestamps stay readable)', () {
      const isoDate = '2026-08-02';
      expect(redactor.redact(isoDate), equals(isoDate));
    });

    test('does NOT redact a date inside a larger message', () {
      const msg = 'Report generated on 2026-08-02 for review';
      expect(redactor.redact(msg), equals(msg));
    });

    test('handles empty and null-safe input', () {
      expect(redactor.redact(''), equals(''));
    });
  });
}
