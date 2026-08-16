import 'package:civic_commons/pii/data/deterministic_pii_filter.dart';
import 'package:civic_commons/pii/data/dictionary_pii_detector.dart';
import 'package:civic_commons/pii/data/local_pii_redaction_pipeline.dart';
import 'package:civic_commons/pii/domain/pii_pipeline_port.dart';
import 'package:civic_commons/pii/domain/pii_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final pipeline = LocalPiiRedactionPipeline(
    localDetector: const DictionaryPiiDetector(),
  );

  group('LocalPiiRedactionPipeline (Task 8.3)', () {
    test('deterministic pass runs BEFORE the contextual detector', () {
      // A phone plus a name: the phone is scrubbed by the dictionary and the
      // name by the local detector — one merged pass, both categories.
      final input = Uint8BufferInput('Rahul called me at +919876543210');
      final result = pipeline.redact(input);

      expect(result.redacted, isNot(contains('9876543210')));
      expect(result.redacted, isNot(contains('Rahul')));
      expect(result.redacted, contains(DeterministicPiiFilter.placeholder));
      expect(result.report.countOf(PiiCategory.phone), 1);
      expect(result.report.countOf(PiiCategory.personName), 1);
    });

    test('AI Boundary Rule: detector sees NO regex-dictionary PII', () {
      final seen = <String>[];
      final spyingDetector = _SpyingDetector(seen);
      final p = LocalPiiRedactionPipeline(localDetector: spyingDetector);

      p.redact(Uint8BufferInput(
          'Rahul\'s phone +919876543210 and email a@b.co and PAN ABCDE1234F'));
      expect(seen, hasLength(1));
      // The raw phone, email, and gov ID must NOT be visible to the local
      // model slot — the deterministic pass scrubbed them first.
      expect(seen.single, isNot(contains('9876543210')));
      expect(seen.single, isNot(contains('a@b.co')));
      expect(seen.single, isNot(contains('ABCDE1234F')));
      // Contextual names ARE the detector's job — it sees them (they are not
      // in the regex dictionary). The boundary is: NO deterministic-dictionary
      // PII ever reaches the model slot.
      expect(seen.single, contains('Rahul'));
    });

    test('MEMORY WIPE PROOF: the plaintext buffer is zeroed after redact', () {
      final input = Uint8BufferInput('contact Priya on +917777777777');
      expect(input.wiped, isFalse);

      pipeline.redact(input);

      expect(input.wiped, isTrue,
          reason: 'the raw plaintext buffer must be all zeros after redaction');
      expect(input.text, isNot(contains('Priya')));
    });

    test('wipe happens even when wipeOnRedact is requested (default)', () {
      final input = Uint8BufferInput('secret api_key=abc123xyz');
      pipeline.redact(input);
      expect(input.wiped, isTrue);
    });
    test('report carries only non-PII aggregate counts', () {
      final result = pipeline.redact(
        Uint8BufferInput('near MG Road, call 9876543210, id 1234 5678 9012'),
      );
      expect(
          result.report.countOf(PiiCategory.address), greaterThanOrEqualTo(1),
          reason: '“MG Road” is a contextual address cue');
      expect(result.report.countOf(PiiCategory.phone), 1);
      expect(result.report.countOf(PiiCategory.aadhaar), 1);
      expect(result.report.totalSpans, greaterThanOrEqualTo(3));
      // The report never contains the plaintext.
      expect(result.report.toString(), isNot(contains('9876543210')));
    });

    test('clean text passes through untouched with an empty report', () {
      final result =
          pipeline.redact(Uint8BufferInput('a perfectly innocent story'));
      expect(result.redacted, 'a perfectly innocent story');
      expect(result.report.isEmpty, isTrue);
    });
  });
}

class _SpyingDetector implements ContextualPiiDetector {
  final List<String> seen;
  _SpyingDetector(this.seen);

  @override
  List<RedactedSpan> detect(String alreadyRedactedText) {
    seen.add(alreadyRedactedText);
    return const DictionaryPiiDetector().detect(alreadyRedactedText);
  }
}
