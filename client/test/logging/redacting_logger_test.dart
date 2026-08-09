import 'package:flutter_test/flutter_test.dart';
import 'package:civic_commons/logging/data/cryptography_hash_provider.dart';
import 'package:civic_commons/logging/data/default_pii_redactor.dart';
import 'package:civic_commons/logging/data/redacting_logger.dart';
import 'package:civic_commons/logging/domain/hash_provider.dart';
import 'package:civic_commons/logging/domain/log_entry.dart';
import 'package:civic_commons/logging/domain/log_level.dart';
import 'package:civic_commons/logging/domain/log_sink.dart';

/// Capturing in-memory sink for asserting what would reach the console.
class CapturingLogSink implements LogSink {
  final List<LogEntry> entries = [];
  final List<String> lines = [];

  @override
  void write(LogEntry entry) {
    entries.add(entry);
    lines.add(entry.message);
  }
}

void main() {
  late CapturingLogSink sink;

  setUp(() {
    sink = CapturingLogSink();
  });

  group('RedactingLogger - PII redaction on free-form logs', () {
    test('redacts phone numbers before they reach the sink', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
      );

      logger.info('Calling +14155552671 now');

      expect(sink.lines.single, isNot(contains('+14155552671')));
      expect(sink.lines.single, contains(DefaultPiiRedactor.placeholder));
    });

    test('redacts emails in error logs too', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
      );

      logger.error('Failed for user@example.com');

      expect(sink.lines.single, isNot(contains('user@example.com')));
    });
  });

  group('RedactingLogger - hash-only logging', () {
    test('writes only the one-way digest, never the raw value', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const CryptographyHashProvider(),
        sink: sink,
      );
      const sensitive = '+14155552671';

      await logger.logHashOnly(description: 'phone', value: sensitive);

      final line = sink.lines.single;
      expect(line, isNot(contains(sensitive)));
      // 64 lowercase hex chars = SHA-256 digest present.
      expect(RegExp(r'phone=[0-9a-f]{64}').hasMatch(line), isTrue);
    });

    test('digest is deterministic and irreversible', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const CryptographyHashProvider(),
        sink: sink,
      );

      await logger.logHashOnly(description: 'val', value: 'secret-data');
      final first = sink.lines.single;

      await logger.logHashOnly(description: 'val', value: 'secret-data');
      final second = sink.lines[1];

      expect(first, equals(second), reason: 'Same input → same digest');
      // The digest is a hash, not the input — the value cannot be recovered.
      expect(first, isNot(contains('secret-data')));
    });
  });

  group('RedactingLogger - boolean crypto logging', () {
    test('logs success as operation=success with no key material', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
      );

      await logger.logCryptoOperation(
        operation: 'argon2id.deriveKeyFromPin',
        success: true,
      );

      expect(sink.lines.single, contains('argon2id.deriveKeyFromPin=success'));
    });

    test('logs failure as operation=failure', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
      );

      await logger.logCryptoOperation(
        operation: 'aes256gcm.decrypt',
        success: false,
      );

      expect(sink.lines.single, contains('aes256gcm.decrypt=failure'));
    });

    test('boolean crypto log never includes payloads or keys', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
      );

      await logger.logCryptoOperation(
        operation: 'deriveKeyFromPin',
        success: true,
        category: 'crypto',
      );

      // Only the boolean outcome + operation name; nothing else.
      expect(sink.lines.single, equals('deriveKeyFromPin=success'));
    });
  });

  group('RedactingLogger - level configuration', () {
    test('debug messages are dropped in production config', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
        config: LogLevelConfig.production,
      );

      logger.debug('verbose debug detail');

      expect(sink.lines, isEmpty);
    });

    test('info and above are kept in production config', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
        config: LogLevelConfig.production,
      );

      logger.info('routine info');
      logger.warning('a warning');
      logger.error('an error');

      expect(sink.lines, hasLength(3));
    });

    test('debug messages are kept in development config', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: sink,
        config: LogLevelConfig.development,
      );

      logger.debug('verbose detail');

      expect(sink.lines, hasLength(1));
    });
  });

  group('RedactingLogger - SECURITY CHECKPOINT (zero plaintext)', () {
    test('no raw payload data ever reaches the sink', () async {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const CryptographyHashProvider(),
        sink: sink,
      );

      // Attempt to log fake PII via every path.
      logger
          .info('Phone +14155552671 email victim@example.com SSN 123-45-6789');
      logger.error(
          'Card 4111 1111 1111 1111 token=5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2');
      await logger.logHashOnly(description: 'secret', value: 'raw-payload-abc');
      await logger.logCryptoOperation(operation: 'decrypt', success: true);

      final joined = sink.lines.join('\n');
      final rawFragments = [
        '+14155552671',
        'victim@example.com',
        '123-45-6789',
        '4111 1111 1111 1111',
        '5a45a983c75655ae014d09052fc80545d7b422fd47ba6640dae2a00a5fbc55b2',
        'raw-payload-abc',
      ];
      for (final fragment in rawFragments) {
        expect(joined, isNot(contains(fragment)),
            reason: 'Raw "$fragment" must never appear in logged output');
      }
    });

    test('a throwing sink never crashes the logger', () {
      final logger = RedactingLogger(
        redactor: const DefaultPiiRedactor(),
        hashProvider: const _FakeHashProvider(),
        sink: _ThrowingSink(),
      );

      // Must not throw.
      logger.info('something');
      logger.error('boom');
    });
  });
}

/// Fixed digest stub for tests that do not care about real hashing.
class _FakeHashProvider implements HashProvider {
  const _FakeHashProvider();

  @override
  Future<String> sha256Hex(String input) async =>
      'a' * 64; // deterministic 64-hex stub
}

class _ThrowingSink implements LogSink {
  @override
  void write(LogEntry entry) {
    throw Exception('sink down');
  }
}
