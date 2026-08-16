import 'dart:io';

import 'package:civic_commons/pii/data/dictionary_pii_detector.dart';
import 'package:civic_commons/pii/data/local_pii_redaction_pipeline.dart';
import 'package:civic_commons/pii/domain/pii_pipeline_port.dart';
import 'package:civic_commons/pii/domain/pii_redaction.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 8.3 SECURITY CHECKPOINT (skill: local-pii-redaction).
///
/// 1. The pipeline is local-only: no cloud AI, no network, no model download
///    — production files import no dart:io/http/WebSocket and print nothing.
/// 2. The deterministic dictionary runs FIRST; the local detector can never
///    see a raw phone/email/gov ID (AI Boundary Rule).
/// 3. Plaintext is wiped immediately after redaction (memory wipe proof).
/// 4. The skill resource files (regex dictionary + local-model prompt) exist
///    in the repository.
void main() {
  group('Task 8.3 SECURITY CHECKPOINT', () {
    test(
        'pipeline production files are local-only — zero networking, no prints',
        () {
      final files = <File>[
        File('lib/pii/domain/pii_redaction.dart'),
        File('lib/pii/domain/pii_pipeline_port.dart'),
        File('lib/pii/data/deterministic_pii_filter.dart'),
        File('lib/pii/data/dictionary_pii_detector.dart'),
        File('lib/pii/data/local_pii_redaction_pipeline.dart'),
      ];
      final forbidden = RegExp(
        "import\\s+['\\\"](dart:io|dart:ffi|package:http|package:web_socket_channel)",
      );
      for (final file in files) {
        final src = file.readAsStringSync();
        expect(forbidden.hasMatch(src), isFalse,
            reason: '${file.path} must not import networking/FFI '
                '(local-only pipeline)');
        expect(src.contains('print('), isFalse,
            reason: '${file.path} must not print');
        expect(src.contains('debugPrint('), isFalse,
            reason: '${file.path} must not debugPrint');
      }
    });

    test('AI Boundary Rule: the local detector never sees dictionary PII', () {
      final seen = <String>[];
      final spying = _SpyingDetector(seen);
      final pipeline = LocalPiiRedactionPipeline(localDetector: spying);

      pipeline.redact(Uint8BufferInput(
          'Rahul: +919876543210, a@b.co, PAN ABCDE1234F, 1234 5678 9012'));
      expect(seen, hasLength(1));
      expect(seen.single, isNot(contains('9876543210')));
      expect(seen.single, isNot(contains('a@b.co')));
      expect(seen.single, isNot(contains('ABCDE1234F')));
      expect(seen.single, isNot(contains('5678')));
    });

    test('memory wipe is unconditional — plaintext is zeroed after redact', () {
      final input = Uint8BufferInput(
          'Priya lives at Sector 14 and her number is 9876501234');
      LocalPiiRedactionPipeline(
        localDetector: const DictionaryPiiDetector(),
      ).redact(input);
      expect(input.wiped, isTrue);
      // The wiped buffer cannot be recovered as text.
      expect(String.fromCharCodes(input.bytes), isNot(contains('Priya')));
    });

    test('wipeOnRedact=false keeps the buffer (opt-out is explicit)', () {
      final input = Uint8BufferInput('api_key=abc', wipeOnRedact: false);
      LocalPiiRedactionPipeline(
        localDetector: const DictionaryPiiDetector(),
      ).redact(input);
      expect(input.wiped, isFalse);
    });

    test('skill resource files exist in the repository', () {
      expect(File('resources/regex/pii_patterns.json').existsSync(), isTrue);
      expect(File('resources/prompts/gemma_redaction_prompt.txt').existsSync(),
          isTrue);
    });

    test('report carries category counts — never plaintext', () {
      final result = LocalPiiRedactionPipeline(
        localDetector: const DictionaryPiiDetector(),
      ).redact(Uint8BufferInput('call 9876543210 about Rahul'));
      expect(result.report.countOf(PiiCategory.phone), 1);
      expect(result.report.countOf(PiiCategory.personName), 1);
      final asString = result.report.toString();
      expect(asString, isNot(contains('9876543210')));
      expect(asString, isNot(contains('Rahul')));
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
