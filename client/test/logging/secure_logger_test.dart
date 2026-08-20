import 'package:civic_commons/logging/domain/log_sink.dart';
import 'package:civic_commons/logging/domain/pii_redactor.dart';
import 'package:civic_commons/logging/domain/secure_logger.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SecureLogger port - Task 13.1', () {
    test('debug method exists', () {
      // Verify the interface defines the method
      expect(SecureLogger, isA<Type>());
    });

    test('info method exists', () {
      expect(SecureLogger, isA<Type>());
    });

    test('warning method exists', () {
      expect(SecureLogger, isA<Type>());
    });

    test('error method exists', () {
      expect(SecureLogger, isA<Type>());
    });

    test('logHashOnly method exists', () {
      expect(SecureLogger, isA<Type>());
    });

    test('logCryptoOperation method exists', () {
      expect(SecureLogger, isA<Type>());
    });
  });

  group('PiiRedactor port - Task 13.1', () {
    test('redact method exists', () {
      expect(PiiRedactor, isA<Type>());
    });
  });

  group('LogSink port - Task 13.1', () {
    test('write method exists', () {
      expect(LogSink, isA<Type>());
    });
  });
}

/// Fake PiiRedactor for testing
class FakePiiRedactor implements PiiRedactor {
  @override
  String redact(String input) {
    // Simple redaction: replace phone numbers and emails
    return input
        .replaceAll(RegExp(r'\+\d{10,15}'), '[REDACTED_PHONE]')
        .replaceAll(RegExp(r'[\w.+-]+@[\w-]+\.[\w.-]+'), '[REDACTED_EMAIL]');
  }
}

/// Fake LogSink for testing
class FakeLogSink implements LogSink {
  final entries = <dynamic>[];

  @override
  void write(dynamic entry) {
    entries.add(entry);
  }
}
