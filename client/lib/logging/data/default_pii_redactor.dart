import '../domain/pii_redactor.dart';

/// Default regex-based [PiiRedactor] (data layer).
///
/// Recognizes and replaces the following sensitive patterns with
/// `[REDACTED]`:
/// - E.164 phone numbers (`+14155552671`)
/// - Email addresses
/// - US Social Security numbers (`123-45-6789`)
/// - Credit card numbers (13–19 digits, optional spaces/dashes)
/// - Long hex tokens / API keys (32+ hex chars — covers blind-hash IDs,
///   secrets, and typical API keys)
/// - Base64 bearer tokens / JWTs (`Bearer eyJ...` and `eyJ...` payloads)
/// - Common key=value secret patterns (`api_key=...`, `password=...`, etc.)
///
/// All patterns are combined into one regex with a single replace pass.
class DefaultPiiRedactor implements PiiRedactor {
  /// Placeholder substituted for every recognized pattern.
  static const String placeholder = '[REDACTED]';

  /// E.164 international phone numbers (`+14155552671`).
  static final RegExp _phone = RegExp(
    r'\+\d[\d\s\-()]{6,17}\d',
  );

  /// Domestic phone numbers with separators (`555-123-4567`).
  static final RegExp _domesticPhone = RegExp(
    r'\b\d{3}[-.]?\d{3}[-.]?\d{4}\b',
  );

  static final RegExp _email = RegExp(
    r'[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}',
  );

  static final RegExp _ssn = RegExp(
    r'\b\d{3}-\d{2}-\d{4}\b',
  );

  static final RegExp _creditCard = RegExp(
    r'\b(?:\d[ -]?){13,18}\d\b',
  );

  /// 32+ consecutive hex chars (tokens, blind-hash IDs, API keys).
  static final RegExp _hexToken = RegExp(
    r'\b[0-9a-fA-F]{32,}\b',
  );

  /// Base64 bearer tokens / JWT fragments.
  static final RegExp _bearerToken = RegExp(
    r'Bearer\s+[A-Za-z0-9\-_.~+/]+=*',
  );

  static final RegExp _jwt = RegExp(
    r'\beyJ[A-Za-z0-9\-_]+\.eyJ[A-Za-z0-9\-_]+\.[A-Za-z0-9\-_]+\b',
  );

  /// `key=value` / `key: value` where key looks like a secret.
  ///
  /// NOTE: Dart's RegExp (ECMAScript engine) does not support inline `(?i)`
  /// flag groups — case-insensitivity must come from the constructor.
  static final RegExp _keyValueSecret = RegExp(
    r'\b(api[_-]?key|secret|password|passwd|token|auth|authorization|private[_-]?key)\b\s*[=:]\s*[^\s,;]+',
    caseSensitive: false,
  );

  static final List<RegExp> _patterns = [
    _ssn,
    _phone,
    _domesticPhone,
    _email,
    _creditCard,
    _hexToken,
    _bearerToken,
    _jwt,
    _keyValueSecret,
  ];

  const DefaultPiiRedactor();

  @override
  String redact(String input) {
    var result = input;
    for (final pattern in _patterns) {
      result = result.replaceAll(pattern, placeholder);
    }
    return result;
  }
}
