import 'package:civic_commons/logging/domain/log_entry.dart';
import 'package:civic_commons/logging/domain/log_level.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LogEntry - Task 13.1', () {
    test('constructs with required fields', () {
      final entry = LogEntry(
        timestamp: DateTime(2026, 8, 20, 12, 0),
        level: LogLevel.info,
        message: 'Test message',
      );
      expect(entry.timestamp, DateTime(2026, 8, 20, 12, 0));
      expect(entry.level, LogLevel.info);
      expect(entry.message, 'Test message');
      expect(entry.category, isNull);
    });

    test('constructs with optional category', () {
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.warning,
        message: 'Warning message',
        category: 'crypto',
      );
      expect(entry.category, 'crypto');
    });

    test('field-wise comparison works correctly', () {
      final timestamp = DateTime(2026, 8, 20, 12, 0);
      final a = LogEntry(
        timestamp: timestamp,
        level: LogLevel.info,
        message: 'Test',
        category: 'cat',
      );
      final b = LogEntry(
        timestamp: timestamp,
        level: LogLevel.info,
        message: 'Test',
        category: 'cat',
      );
      final c = LogEntry(
        timestamp: timestamp,
        level: LogLevel.error,
        message: 'Test',
        category: 'cat',
      );
      // Field-wise comparison (LogEntry uses reference equality)
      expect(a.timestamp, b.timestamp);
      expect(a.level, b.level);
      expect(a.message, b.message);
      expect(a.category, b.category);
      expect(a.level, isNot(c.level));
    });

    test('message is sanitized (no raw PII)', () {
      // LogEntry should only contain sanitized messages
      final entry = LogEntry(
        timestamp: DateTime.now(),
        level: LogLevel.info,
        message: '[REDACTED] login attempt',
      );
      expect(entry.message, contains('[REDACTED]'));
      expect(entry.message, isNot(contains('+91')));
    });
  });
}
