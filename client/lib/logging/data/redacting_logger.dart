import '../domain/hash_provider.dart';
import '../domain/log_entry.dart';
import '../domain/log_level.dart';
import '../domain/log_sink.dart';
import '../domain/pii_redactor.dart';
import '../domain/secure_logger.dart';

/// Concrete [SecureLogger] (data layer) that enforces the zero-plaintext
/// policy at every path:
///
/// - Free-form messages are passed through the [PiiRedactor] BEFORE any sink
///   can see them.
/// - `logHashOnly` writes only the one-way SHA-256 digest of a sensitive
///   value — the raw value never exists in any emitted line.
/// - `logCryptoOperation` writes only `operation → success|failure`.
/// - Level filtering via [LogLevelConfig] (debug excluded in production).
///
/// SECURITY CHECKPOINT (Task 2.7): Because redaction happens inside this
/// facade, no caller can accidentally reach a sink with raw payload data —
/// the only object a sink ever receives is a sanitized [LogEntry].
class RedactingLogger implements SecureLogger {
  final PiiRedactor _redactor;
  final HashProvider _hashProvider;
  final LogSink _sink;
  final LogLevelConfig _config;

  RedactingLogger({
    required PiiRedactor redactor,
    required HashProvider hashProvider,
    required LogSink sink,
    LogLevelConfig config = LogLevelConfig.development,
  })  : _redactor = redactor,
        _hashProvider = hashProvider,
        _sink = sink,
        _config = config;

  @override
  void debug(String message, {String? category}) =>
      _log(LogLevel.debug, message, category: category);

  @override
  void info(String message, {String? category}) =>
      _log(LogLevel.info, message, category: category);

  @override
  void warning(String message, {String? category}) =>
      _log(LogLevel.warning, message, category: category);

  @override
  void error(String message, {String? category}) =>
      _log(LogLevel.error, message, category: category);

  @override
  Future<void> logHashOnly({
    required String description,
    required String value,
    String? category,
  }) async {
    if (!_config.shouldEmit(LogLevel.info)) {
      return;
    }
    // The raw value is hashed and immediately discarded — only the digest
    // is placed in the message. The digest is one-way, so the log cannot be
    // reversed to recover the value. The description is redacted too so no
    // caller-supplied text can smuggle PII past the facade.
    final String digest;
    try {
      digest = await _hashProvider.sha256Hex(value);
    } catch (_) {
      // Logging must never crash the app.
      return;
    }
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      category: category,
      message: '${_redactor.redact(description)}=$digest',
    ));
  }

  @override
  Future<void> logCryptoOperation({
    required String operation,
    required bool success,
    String? category,
  }) async {
    if (!_config.shouldEmit(LogLevel.info)) {
      return;
    }
    // Boolean-only indicator: never keys, PINs, ciphertext, or payloads.
    // The operation name is redacted so caller-supplied text cannot smuggle
    // PII into the log.
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: success ? LogLevel.info : LogLevel.error,
      category: category,
      message:
          '${_redactor.redact(operation)}=${success ? 'success' : 'failure'}',
    ));
  }

  void _log(LogLevel level, String message, {String? category}) {
    if (!_config.shouldEmit(level)) {
      return;
    }
    _emit(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      category: category,
      message: _redactor.redact(message),
    ));
  }

  void _emit(LogEntry entry) {
    try {
      _sink.write(entry);
    } catch (_) {
      // Logging must never crash the app.
    }
  }
}
