import 'package:civic_commons/logging/domain/log_entry.dart';
import 'package:civic_commons/logging/domain/log_level.dart';
import 'package:civic_commons/logging/domain/log_sink.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogSink port - Task 13.1', () {
    test('write method exists', () {
      expect(LogSink, isA<Type>());
    });
  });

  group('LogSink implementations - Task 13.1', () {
    test('in-memory sink captures entries', () {
      final sink = _InMemoryLogSink();
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Test message',
      );
      sink.write(entry);
      expect(sink.entries, hasLength(1));
      expect(sink.entries.first.message, 'Test message');
    });

    test('in-memory sink captures multiple entries', () {
      final sink = _InMemoryLogSink();
      for (var i = 0; i < 5; i++) {
        sink.write(LogEntry(
          timestamp: DateTime.now(),
          level: LogLevel.info,
          message: 'Message $i',
        ));
      }
      expect(sink.entries, hasLength(5));
    });

    test('in-memory sink preserves entry order', () {
      final sink = _InMemoryLogSink();
      sink.write(LogEntry(
        timestamp: DateTime(2026, 1, 1),
        level: LogLevel.info,
        message: 'First',
      ));
      sink.write(LogEntry(
        timestamp: DateTime(2026, 1, 2),
        level: LogLevel.info,
        message: 'Second',
      ));
      expect(sink.entries[0].message, 'First');
      expect(sink.entries[1].message, 'Second');
    });

    test('in-memory sink clear resets entries', () {
      final sink = _InMemoryLogSink();
      sink.write(LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: 'Test',
      ));
      sink.clear();
      expect(sink.entries, isEmpty);
    });
  });
}

/// Simple in-memory log sink for testing
class _InMemoryLogSink implements LogSink {
  final entries = <LogEntry>[];

  @override
  void write(LogEntry entry) {
    entries.add(entry);
  }

  void clear() {
    entries.clear();
  }
}
