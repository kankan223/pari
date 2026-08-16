import '../domain/pii_pipeline_port.dart';
import '../domain/pii_redaction.dart';

/// Deterministic regex dictionary filter (Task 8.3, skill step 1).
///
/// Recognizes and replaces the standard PII dictionary with a single
/// placeholder — phones (E.164 + Indian mobile), e-mails, Indian government
/// IDs (Aadhaar, PAN), US SSNs, credit cards, long hex tokens / blind-hash
/// IDs, bearer tokens / JWTs, and common key=value secrets. The pattern set
/// is FIXED and local — no cloud AI, no network (MASTER_PLAN §8.3, §5
/// "No Cloud AI for PII").
///
/// SECURITY CHECKPOINT: spans carry only category + offsets — the matched
/// plaintext is never returned. Overlapping matches across categories are
/// merged into ONE placeholder so a value can never survive nested between
/// two patterns.
class DeterministicPiiFilter {
  /// Placeholder substituted for every recognized span.
  static const String placeholder = '[REDACTED]';

  static final RegExp _phoneE164 = RegExp(
    r'\+[1-9][0-9\s\-()]{6,17}[0-9]',
  );

  /// Indian mobile numbers (10 digits, optional 91/+91 prefix).
  static final RegExp _phoneInMobile = RegExp(
    r'(?<![0-9])(?:\+?91[\s\-]?)?[6-9][0-9]{9}(?![0-9])',
  );

  static final RegExp _domesticPhone = RegExp(
    r'\b[0-9]{3}[-.]?[0-9]{3}[-.]?[0-9]{4}\b',
  );

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );

  /// Aadhaar: exactly 12 digits, optionally grouped 4-4-4 (India, DPDP
  /// context). The alternation is ordered long-to-short so a 12-digit run
  /// consumes fully (no partial 4-8 grouping).
  static final RegExp _aadhaar = RegExp(
    r'(?<![0-9])(?:[0-9]{4}[\s\-]?[0-9]{4}[\s\-]?[0-9]{4}|[0-9]{12})(?![0-9])',
  );

  /// PAN: 5 uppercase letters + 4 digits + 1 uppercase letter.
  static final RegExp _pan = RegExp(
    r'(?<![A-Z0-9])[A-Z]{5}[0-9]{4}[A-Z](?![A-Z0-9])',
  );

  static final RegExp _ssn = RegExp(
    r'\b[0-9]{3}-[0-9]{2}-[0-9]{4}\b',
  );

  static final RegExp _creditCard = RegExp(
    r'\b(?:[0-9][ -]?){13,18}[0-9]\b',
  );

  /// 32+ consecutive hex chars (blind-hash IDs, tokens, API keys).
  static final RegExp _hexToken = RegExp(
    r'\b[0-9a-fA-F]{32,}\b',
  );

  static final RegExp _bearerToken = RegExp(
    r'Bearer\s+[A-Za-z0-9\-_.~+/]+=*',
  );

  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]{4,}\b',
  );

  /// `key=value` / `key: value` where the key names a secret.
  static final RegExp _keyValueSecret = RegExp(
    r'\b(api[_-]?key|secret|password|passwd|token|auth|authorization|private[_-]?key)\b\s*[=:]\s*[^\s,;]+',
    caseSensitive: false,
  );

  /// Pattern → category pairs, applied in a single merged pass.
  static final List<(RegExp, PiiCategory)> _dictionary = [
    (_ssn, PiiCategory.ssn),
    (_phoneE164, PiiCategory.phone),
    (_domesticPhone, PiiCategory.phone),
    (_phoneInMobile, PiiCategory.phone),
    (_email, PiiCategory.email),
    (_aadhaar, PiiCategory.aadhaar),
    (_pan, PiiCategory.pan),
    (_creditCard, PiiCategory.creditCard),
    (_hexToken, PiiCategory.hexToken),
    (_bearerToken, PiiCategory.bearerToken),
    (_jwt, PiiCategory.bearerToken),
    (_keyValueSecret, PiiCategory.keyValueSecret),
  ];

  const DeterministicPiiFilter();

  /// All recognized (category, span) pairs in [input], merged so that no
  /// two spans overlap (first pattern wins; overlapping later spans are
  /// dropped — a single placeholder still covers the whole region).
  List<RedactedSpan> findSpans(String input) {
    final raw = <RedactedSpan>[];
    for (final (pattern, category) in _dictionary) {
      for (final match in pattern.allMatches(input)) {
        raw.add(RedactedSpan(
          category: category,
          start: match.start,
          end: match.end,
        ));
      }
    }
    raw.sort((a, b) => a.start != b.start ? a.start - b.start : b.end - a.end);
    final merged = <RedactedSpan>[];
    for (final span in raw) {
      if (merged.isNotEmpty && span.start < merged.last.end) {
        // Overlaps the previous span — extend it instead of double-reporting.
        if (span.end > merged.last.end) {
          merged[merged.length - 1] = RedactedSpan(
            category: merged.last.category,
            start: merged.last.start,
            end: span.end,
          );
        }
        continue;
      }
      merged.add(span);
    }
    return merged;
  }

  /// Replaces every recognized span with a single placeholder (right-to-left
  /// so offsets stay valid). Returns the redacted text + non-PII report.
  PiiRedactionResult redact(String input) {
    final spans = findSpans(input);
    final counts = <PiiCategory, int>{};
    for (final span in spans) {
      counts[span.category] = (counts[span.category] ?? 0) + 1;
    }
    final buffer = input.split('');
    for (final span in spans.reversed) {
      buffer.replaceRange(span.start, span.end, [placeholder]);
    }
    return PiiRedactionResult(
      redacted: buffer.join(),
      report: PiiRedactionReport(counts),
    );
  }
}
