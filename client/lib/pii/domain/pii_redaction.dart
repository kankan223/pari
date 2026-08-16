/// Categories of personally-identifiable / sensitive content recognized by
/// the redaction pipeline (Task 8.3).
///
/// SECURITY CHECKPOINT: category names are fixed wire-safe strings — they
/// never contain user data, and the pipeline never returns the ORIGINAL
/// plaintext of a span, only its category + position.
enum PiiCategory {
  phone('phone'),
  email('email'),
  aadhaar('aadhaar'),
  pan('pan'),
  ssn('ssn'),
  creditCard('credit_card'),
  hexToken('hex_token'),
  bearerToken('bearer_token'),
  keyValueSecret('key_value_secret'),
  personName('person_name'),
  address('address');

  const PiiCategory(this.wireName);

  /// Fixed wire-safe category name (never user-derived).
  final String wireName;
}

/// A single detected sensitive span in the INPUT text (Task 8.3).
///
/// Carries ONLY the category + [start]/[end] offsets into the source text —
/// never the matched plaintext. The UI/logs may render the category name but
/// never the span content.
class RedactedSpan {
  final PiiCategory category;
  final int start;
  final int end;

  const RedactedSpan({
    required this.category,
    required this.start,
    required this.end,
  });
}

/// Count of spans found per category (Task 8.3 verification surface).
///
/// This is the ONLY per-content signal the pipeline returns to callers — a
/// non-PII aggregate. It is safe to log and safe to show in UI status lines.
class PiiRedactionReport {
  final Map<PiiCategory, int> _counts;

  const PiiRedactionReport(this._counts);

  /// Total spans redacted across all categories.
  int get totalSpans => _counts.values.fold(0, (sum, count) => sum + count);

  /// Spans of [category] found (0 when none).
  int countOf(PiiCategory category) => _counts[category] ?? 0;

  bool get isEmpty => totalSpans == 0;
}
