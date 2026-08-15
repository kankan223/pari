/// Port (domain boundary) for redacting personally-identifiable information
/// (and other sensitive patterns) from free-form text before it is logged.
///
/// Clean Architecture: the domain depends only on this abstract interface;
/// the pattern implementation lives in the data layer and is injected at
/// composition time. Tests inject a fake or use the real one.
///
/// Security contract:
/// - [redact] must be total: given ANY input, it returns text with every
///   recognized PII/sensitive pattern replaced by a placeholder. It never
///   throws and never leaks the original value.
abstract class PiiRedactor {
  /// Returns [input] with all recognized sensitive patterns replaced by a
  /// fixed placeholder such as `[REDACTED]`.
  String redact(String input);
}
