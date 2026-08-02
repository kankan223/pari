import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/logging/data/console_log_sink.dart';
import 'package:civic_commons/logging/domain/log_entry.dart';
import 'package:civic_commons/logging/domain/log_level.dart';

LogEntry _entry(LogLevel level, String message, {String? category}) => LogEntry(
      timestamp: DateTime.fromMillisecondsSinceEpoch(0),
      level: level,
      message: message,
      category: category,
    );

void main() {
  group('ConsoleLogSink', () {
    test('formats level and message with the injected emitter', () {
      final lines = <String>[];
      final sink = ConsoleLogSink(emitter: lines.add);

      sink.write(_entry(LogLevel.info, 'hello'));

      expect(lines.single, equals('[INFO] hello'));
    });

    test('includes the category in the prefix when provided', () {
      final lines = <String>[];
      final sink = ConsoleLogSink(emitter: lines.add);

      sink.write(_entry(LogLevel.error, 'decrypt=failure', category: 'crypto'));

      expect(lines.single, equals('[ERROR][crypto] decrypt=failure'));
    });

    test('maps each level to its tag', () {
      final lines = <String>[];
      final sink = ConsoleLogSink(emitter: lines.add);

      sink.write(_entry(LogLevel.debug, 'a'));
      sink.write(_entry(LogLevel.info, 'b'));
      sink.write(_entry(LogLevel.warning, 'c'));
      sink.write(_entry(LogLevel.error, 'd'));

      expect(lines[0], startsWith('[DEBUG]'));
      expect(lines[1], startsWith('[INFO]'));
      expect(lines[2], startsWith('[WARN]'));
      expect(lines[3], startsWith('[ERROR]'));
    });

    test('default emitter exists (debugPrint) without crashing', () {
      // Constructing with the default emitter must not throw.
      final sink = ConsoleLogSink();
      sink.write(_entry(LogLevel.info, 'sanitized-only'));
    });
  });
}
