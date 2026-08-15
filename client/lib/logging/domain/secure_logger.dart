import 'log_level.dart';

/// Port (domain use case) for the application's secure logging facade.
///
/// This is the ONLY logging entry point application code should use. It
/// enforces the zero-plaintext policy at the API level:
///
/// 1. **Redacted logging** — free-form messages are passed through a
///    [PiiRedactor] before anything can be written.
/// 2. **Hash-only logging** — sensitive values are written ONLY as their
///    one-way SHA-256 digest; the raw value never reaches a sink.
/// 3. **Boolean crypto logging** — cryptographic operations are logged as
///    `operation → success/failure` indicators, never with keys or payloads.
/// 4. **Level filtering** — the configured [LogLevelConfig] decides what is
///    emitted (debug is structurally excluded in production).
///
/// Clean Architecture: the domain depends only on this abstract interface;
/// the enforcement implementation lives in the data layer.
///
/// SECURITY CHECKPOINT (Task 2.7): No method here — and no implementation of
/// it — may ever cause `print()`/`debugPrint()` (or any sink) to receive raw
/// payload data. Every path sanitizes before write.
abstract class SecureLogger {
  /// Logs at [LogLevel.debug] (development only).
  void debug(String message, {String? category});

  /// Logs at [LogLevel.info].
  void info(String message, {String? category});

  /// Logs at [LogLevel.warning].
  void warning(String message, {String? category});

  /// Logs at [LogLevel.error].
  void error(String message, {String? category});

  /// Logs a sensitive value as its one-way hash only.
  ///
  /// Parameters:
  /// - description: what the value is (e.g. 'blind_hash_id') — this is the
  ///   human-readable part and must itself be non-sensitive
  /// - value: the sensitive value to hash; NEVER written raw
  /// - category: optional log category
  ///
  /// Security: [value] is hashed in memory and only the digest is written.
  Future<void> logHashOnly({
    required String description,
    required String value,
    String? category,
  });

  /// Logs a cryptographic operation as a boolean success/failure indicator.
  ///
  /// Parameters:
  /// - operation: the operation name (e.g. 'argon2id.deriveKeyFromPin')
  /// - success: whether the operation succeeded
  /// - category: optional log category
  ///
  /// Security: never includes keys, ciphertext, PINs, or payload data — only
  /// the operation name and a boolean outcome.
  Future<void> logCryptoOperation({
    required String operation,
    required bool success,
    String? category,
  });
}
