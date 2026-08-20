import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regex for detecting forbidden networking imports.
  final networkingImport = RegExp(
    "import\\s+['\"](?:dart:io|package:http|package:web_socket_channel)",
  );

  final printPattern = RegExp(r'\b(?:print|debugPrint)\s*\(');

  group('Database Performance Security Checkpoint - Task 12.2', () {
    test('domain files import no networking packages', () {
      final files = [
        'lib/database/domain/index_manager.dart',
        'lib/database/domain/batch_writer.dart',
        'lib/database/domain/statement_cache.dart',
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        final matches = networkingImport.allMatches(source).toList();
        expect(
          matches,
          isEmpty,
          reason: '$path contains networking import',
        );
      }
    });

    test('data files import no networking packages', () {
      final files = [
        'lib/database/data/in_memory_index_manager.dart',
        'lib/database/data/in_memory_batch_writer.dart',
        'lib/database/data/in_memory_statement_cache.dart',
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        final matches = networkingImport.allMatches(source).toList();
        expect(
          matches,
          isEmpty,
          reason: '$path contains networking import',
        );
      }
    });

    test('domain files contain no print or debugPrint', () {
      final files = [
        'lib/database/domain/index_manager.dart',
        'lib/database/domain/batch_writer.dart',
        'lib/database/domain/statement_cache.dart',
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        final matches = printPattern.allMatches(source).toList();
        expect(
          matches,
          isEmpty,
          reason: '$path contains print/debugPrint statement',
        );
      }
    });

    test('data files contain no print or debugPrint', () {
      final files = [
        'lib/database/data/in_memory_index_manager.dart',
        'lib/database/data/in_memory_batch_writer.dart',
        'lib/database/data/in_memory_statement_cache.dart',
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        final matches = printPattern.allMatches(source).toList();
        expect(
          matches,
          isEmpty,
          reason: '$path contains print/debugPrint statement',
        );
      }
    });

    test('no PII-shaped literals in domain files', () {
      final files = [
        'lib/database/domain/index_manager.dart',
        'lib/database/domain/batch_writer.dart',
        'lib/database/domain/statement_cache.dart',
      ];
      final piiPatterns = [
        RegExp(r'\+\d{10,15}'), // E.164 phone
        RegExp(r'\b[\w.+-]+@[\w-]+\.[\w.-]+\b'), // Email
        RegExp(r'\b[0-9a-f]{64}\b'), // 64-hex hash
        RegExp(r'\buser_id\b', caseSensitive: false),
        RegExp(r'\bphone\b', caseSensitive: false),
        RegExp(r'\bemail\b', caseSensitive: false),
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        for (final pattern in piiPatterns) {
          final matches = pattern.allMatches(source).toList();
          expect(
            matches,
            isEmpty,
            reason: '$path contains PII pattern: ${pattern.pattern}',
          );
        }
      }
    });

    test('index definitions carry no PII fields', () {
      final file = File('lib/database/data/in_memory_index_manager.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      // Index names should not contain raw PII fields
      // Note: actor_hash is a BLINDED hash column, not raw identity
      expect(source, isNot(contains('phone')));
      expect(source, isNot(contains('email')));
      expect(source, isNot(contains('user_name')));
      expect(source, isNot(contains('real_name')));
    });

    test('batch operations carry no identity fields', () {
      final file = File('lib/database/domain/batch_writer.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      // Batch operations are table/row/name based, no identity
      expect(source, isNot(contains('phone')));
      expect(source, isNot(contains('email')));
    });
  });
}
