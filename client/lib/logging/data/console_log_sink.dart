import 'package:flutter/foundation.dart' show debugPrint;

import '../domain/log_entry.dart';
import '../domain/log_level.dart';
import '../domain/log_sink.dart';

/// Writes sanitized [LogEntry]s to a destination (data layer).
///
/// This is the production console sink: it formats an entry and forwards it
/// to an injectable emitter function. The default emitter uses Flutter's
/// `debugPrint`, which is the sanctioned console output in Flutter apps.
///
/// SECURITY CHECKPOINT (Task 2.7): This sink can ONLY ever receive entries
/// that were already sanitized by the [RedactingLogger] — it has no way to
/// re-introduce raw data. The emitter is injected so tests can capture
/// output and assert no raw payload ever reaches it.
class ConsoleLogSink implements LogSink {
  /// The emitter that ultimately writes the formatted line.
  final void Function(String line) emitter;

  ConsoleLogSink({void Function(String line)? emitter})
      : emitter = emitter ?? _debugPrintLine;

  @override
  void write(LogEntry entry) {
    final levelTag = _levelTag(entry.level);
    final category = entry.category;
    final prefix =
        category == null ? '[$levelTag] ' : '[$levelTag][$category] ';
    emitter('$prefix${entry.message}');
  }

  static String _levelTag(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return 'DEBUG';
      case LogLevel.info:
        return 'INFO';
      case LogLevel.warning:
        return 'WARN';
      case LogLevel.error:
        return 'ERROR';
    }
  }

  static void _debugPrintLine(String line) {
    // debugPrint is Flutter's batched, truncation-safe console writer.
    debugPrint(line);
  }
}
