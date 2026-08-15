import 'log_level.dart';

/// A single, fully-sanitized log entry.
///
/// By the time an entry is constructed its [message] MUST already be free of
/// PII and raw payloads: the only content allowed here is redacted text,
/// hashes, or boolean indicators. The sink may safely write it anywhere.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;

  /// Optional classification (e.g. 'crypto', 'identity', 'sync').
  final String? category;

  /// Sanitized message — never contains raw PII or payload data.
  final String message;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.category,
  });
}
