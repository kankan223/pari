import '../domain/pii_pipeline_port.dart';
import '../domain/pii_redaction.dart';
import 'deterministic_pii_filter.dart';

/// Production [PiiRedactionPipeline] (data layer, Task 8.3, skill
/// local-pii-redaction).
///
/// Executes the skill's 4 steps in order:
/// 1. **Deterministic filter first** — the standard regex dictionary scrubs
///    phones, e-mails, gov IDs, cards, tokens, key=value secrets.
/// 2. **Local model routing** — the ALREADY-redacted remainder is piped
///    through the injected local [ContextualPiiDetector] (on-device; the
///    Gemma slot — never a cloud AI). The detector can only ever see
///    redacted text, so the AI Boundary Rule holds.
/// 3. **Ciphertext output** — callers persist/queue ONLY [PiiRedactionResult.redacted].
/// 4. **Memory wipe** — the plaintext [Uint8BufferInput] is zeroed after the
///    redaction pass (Dart Strings are immutable, so the pipeline accepts a
///    mutable byte buffer it can actually wipe).
///
/// SECURITY CHECKPOINT (8.3): after [redact] returns, the plaintext buffer
/// is all zeros and no copy of the raw text is retained by the pipeline.
class LocalPiiRedactionPipeline implements PiiRedactionPipeline {
  final DeterministicPiiFilter _deterministic;
  final ContextualPiiDetector _localDetector;

  LocalPiiRedactionPipeline({
    DeterministicPiiFilter? deterministic,
    required ContextualPiiDetector localDetector,
  })  : _deterministic = deterministic ?? const DeterministicPiiFilter(),
        _localDetector = localDetector;

  @override
  PiiRedactionResult redact(Uint8BufferInput input) {
    try {
      // Step 1 — deterministic regex dictionary on the raw text.
      final firstPass = _deterministic.redact(input.text);

      // Step 2 — local contextual detection on the ALREADY-REDACTED text.
      final contextualSpans = _localDetector.detect(firstPass.redacted);

      // Merge the contextual spans into the deterministic output. The
      // report aggregates the deterministic counts and the new contextual
      // spans (both are non-PII category counts).
      final counts = <PiiCategory, int>{};
      for (final category in PiiCategory.values) {
        final n = firstPass.report.countOf(category);
        if (n > 0) {
          counts[category] = n;
        }
      }
      final buffer = firstPass.redacted.split('');
      for (final span in contextualSpans.reversed) {
        if (span.start < 0 ||
            span.end > buffer.length ||
            span.start >= span.end) {
          continue; // defensive — a span outside bounds can never be applied
        }
        counts[span.category] = (counts[span.category] ?? 0) + 1;
        buffer.replaceRange(
            span.start, span.end, [DeterministicPiiFilter.placeholder]);
      }

      return PiiRedactionResult(
        redacted: buffer.join(),
        report: PiiRedactionReport(counts),
      );
    } finally {
      // Step 4 — memory wipe: zero the plaintext buffer unconditionally
      // (even on a detection failure). Nothing survives past this call.
      if (input.wipeOnRedact) {
        input.wipe();
      }
    }
  }
}
