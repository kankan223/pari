import 'package:civic_commons/pii/data/dictionary_pii_detector.dart';
import 'package:civic_commons/pii/domain/pii_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const detector = DictionaryPiiDetector();

  group('DictionaryPiiDetector (Task 8.3)', () {
    test('detects person names from the bounded dictionary', () {
      final spans = detector.detect('talked to Priya about the incident');
      expect(spans, hasLength(1));
      expect(spans.single.category, PiiCategory.personName);
      // Offsets: "talked to " (10) .. "Priya" (10+5).
      expect(spans.single.start, 10);
      expect(spans.single.end, 15);
    });

    test('detects names case-insensitively', () {
      final spans = detector.detect('RAHUL and rahul both appeared');
      expect(spans.where((s) => s.category == PiiCategory.personName),
          hasLength(2));
    });

    test('does not match name fragments inside longer words', () {
      // "rahul" inside "brahulhouse" must NOT match (word boundary).
      expect(detector.detect('the brahulhouse is big'), isEmpty);
    });

    test('detects coarse address cues', () {
      final spans = detector.detect('we met near MG Road in the evening');
      expect(spans.any((s) => s.category == PiiCategory.address), isTrue);
      expect(spans.any((s) => s.category == PiiCategory.personName), isFalse);
    });

    test('returns category+offset spans — never the matched plaintext', () {
      final spans = detector.detect('Rahul lives at Sector 14');
      expect(spans, isNotEmpty);
      for (final span in spans) {
        // No field carries the matched text.
        expect(span.toString(), isNot(contains('Rahul')));
        expect(span.toString(), isNot(contains('Sector')));
      }
    });

    test('empty / clean text yields no spans', () {
      expect(detector.detect(''), isEmpty);
      expect(detector.detect('no sensitive content here'), isEmpty);
    });
  });
}
