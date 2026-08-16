import 'package:civic_commons/pii/data/deterministic_pii_filter.dart';
import 'package:civic_commons/pii/domain/pii_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const filter = DeterministicPiiFilter();
  const p = DeterministicPiiFilter.placeholder;

  group('DeterministicPiiFilter (Task 8.3)', () {
    test('redacts E.164 and Indian mobile phone numbers', () {
      final r = filter.redact('Call +919876543210 or +1 415 555 2671 today');
      expect(r.redacted, contains(p));
      expect(r.redacted, isNot(contains('9876543210')));
      expect(r.report.countOf(PiiCategory.phone), 2);
    });

    test('redacts Indian mobile numbers with and without 91 prefix', () {
      expect(filter.redact('msg me at 9876543210').redacted, contains(p));
      expect(filter.redact('msg me at 9176543210').redacted, contains(p));
      // 6-digit numbers are NOT phones.
      expect(filter.redact('pin 123456 is fine').redacted, isNot(contains(p)));
    });

    test('redacts email addresses', () {
      final r = filter.redact('reach priya.sharma@example.com please');
      expect(r.redacted, isNot(contains('priya.sharma@example.com')));
      expect(r.report.countOf(PiiCategory.email), 1);
    });

    test('redacts Aadhaar (grouped and continuous)', () {
      final grouped = filter.redact('aadhaar 1234 5678 9012 on file').redacted;
      expect(grouped, isNot(contains('5678')));
      expect(grouped, contains(p));
      final continuous = filter.redact('id 123456789012').redacted;
      expect(continuous, isNot(contains('123456789012')));
      expect(
          filter.redact('123456789012').report.countOf(PiiCategory.aadhaar), 1);
    });

    test('redacts PAN card numbers', () {
      final r = filter.redact('PAN ABCDE1234F provided');
      expect(r.redacted, isNot(contains('ABCDE1234F')));
      expect(r.report.countOf(PiiCategory.pan), 1);
    });

    test('redacts SSN and credit cards', () {
      expect(filter.redact('ssn 123-45-6789').redacted, contains(p));
      final cc = filter.redact('card 4111 1111 1111 1111 ok').redacted;
      expect(cc, isNot(contains('4111')));
    });

    test('redacts 32+ hex tokens (blind hashes) and bearer/JWT tokens', () {
      const hash =
          'a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f4a5b6c7d8e9f0a1b2';
      expect(filter.redact('hash $hash').redacted, contains(p));
      expect(
          filter
              .redact(
                  'Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature')
              .redacted,
          contains(p));
      expect(
        filter
            .redact(
                'Bearer eyJhbGciOiJSUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.signature')
            .report
            .countOf(PiiCategory.bearerToken),
        1,
      );
    });

    test('redacts key=value secrets', () {
      final r = filter.redact('api_key=sk_live_12345 password=hunter2');
      expect(r.redacted, isNot(contains('hunter2')));
      expect(r.redacted, isNot(contains('sk_live_12345')));
      expect(r.report.countOf(PiiCategory.keyValueSecret), 2);
    });

    test('overlapping spans merge into a single placeholder', () {
      // "secret=value@example.com" — the key=value pattern (value has no
      // spaces so it spans the email) overlaps the email pattern. Merged.
      final r = filter.redact('creds secret=foo@example.com here');
      final merged = r.redacted;
      expect(merged, isNot(contains('foo@example.com')));
      expect(RegExp(RegExp.escape(p)).allMatches(merged).length, 1,
          reason: 'overlapping spans must collapse into ONE placeholder');
    });

    test('redaction is total — never throws, never leaks originals', () {
      expect(filter.redact('').redacted, '');
      expect(() => filter.redact('a' * 5000), returnsNormally);
      final r = filter.redact('narrative with no PII at all');
      expect(r.redacted, 'narrative with no PII at all');
      expect(r.report.isEmpty, isTrue);
    });
  });
}
