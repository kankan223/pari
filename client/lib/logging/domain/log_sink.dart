import 'log_entry.dart';

/// Port (domain boundary) for where sanitized [LogEntry]s are written.
///
/// The domain logger produces fully-redacted entries and hands them to a
/// [LogSink]; the sink is responsible only for output (console, file,
/// crash-reporting). Because entries are sanitized before reaching the sink,
/// no sink implementation can ever emit raw PII or payload data.
///
/// Clean Architecture: the domain depends only on this abstract interface.
/// The concrete output implementation (e.g. console via debugPrint) lives in
/// the data layer and is injected at composition time. Tests use an
/// in-memory capturing sink.
abstract class LogSink {
  /// Writes a sanitized entry. Must never throw.
  void write(LogEntry entry);
}
