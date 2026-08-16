import 'pii_redaction.dart';

/// Port for the PII redaction pipeline (Task 8.3, skill: local-pii-redaction).
///
/// The pipeline enforces the AI Boundary Rule in one place: NO unredacted
/// plaintext may cross into a queue, a wire envelope, or a cloud API. It
/// runs the deterministic regex dictionary FIRST, then routes the
/// already-redacted remainder through a LOCAL contextual detector (never a
/// cloud AI). The result is a redacted string + a non-PII aggregate report.
abstract class PiiRedactionPipeline {
  /// Redacts [input] in place of its plaintext life:
  /// 1. deterministic regex filter (phones, e-mails, gov IDs, tokens),
  /// 2. local contextual detection on the ALREADY-redacted remainder,
  /// 3. the input buffer is wiped / released after redaction.
  ///
  /// Returns the redacted text (callers persist/queue ONLY this) and the
  /// [PiiRedactionReport] (safe-to-log aggregate counts).
  PiiRedactionResult redact(Uint8BufferInput input);
}

/// A mutable plaintext buffer — the ONLY input form the pipeline accepts.
///
/// Dart `String`s are immutable and cannot be zeroed; to honor the wipe
/// requirement (MASTER_PLAN 8.3) the pipeline accepts the raw text as a
/// mutable byte buffer it can overwrite with zeros after redaction.
class Uint8BufferInput {
  final List<int> bytes;
  final bool _wipeOnRedact;

  Uint8BufferInput(String text, {bool wipeOnRedact = true})
      : bytes = List<int>.from(text.codeUnits),
        _wipeOnRedact = wipeOnRedact;

  String get text => String.fromCharCodes(bytes);

  /// Zeroes the buffer (memory wipe). Idempotent.
  void wipe() {
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = 0;
    }
  }

  /// True when the caller asked the pipeline to wipe after redaction.
  bool get wipeOnRedact => _wipeOnRedact;

  /// All bytes are zero (post-wipe proof for the security checkpoint).
  bool get wiped => bytes.every((b) => b == 0);
}

/// Result of one [PiiRedactionPipeline.redact] pass.
class PiiRedactionResult {
  final String redacted;
  final PiiRedactionReport report;

  const PiiRedactionResult({
    required this.redacted,
    required this.report,
  });
}

/// Port for LOCAL contextual PII detection (names, addresses).
///
/// SECURITY CHECKPOINT: the detector receives ONLY already-redacted text —
/// the deterministic pass has already replaced recognized patterns with
/// placeholders, so the local model (or in-memory stand-in) can never see a
/// raw phone, e-mail, or government ID. It is local-only: no cloud AI, no
/// network. Returns additional [RedactedSpan]s with no matched plaintext.
abstract class ContextualPiiDetector {
  /// Detects contextual PII spans in [alreadyRedactedText].
  List<RedactedSpan> detect(String alreadyRedactedText);
}
