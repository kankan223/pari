import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regex for detecting forbidden networking imports in Dart source files.
  // Uses a normal (non-raw) string to avoid Dart raw-string quote issues.
  final networkingImport = RegExp(
    "import\\s+['\"](?:dart:io|package:http|package:web_socket_channel)",
  );

  final printPattern = RegExp(r'\b(?:print|debugPrint)\s*\(');

  group('Performance Module Security Checkpoint - Task 12.1', () {
    test('domain files import no networking packages', () {
      final files = [
        'lib/performance/domain/lazy_load_config.dart',
        'lib/performance/domain/image_compression_config.dart',
        'lib/performance/domain/performance_metrics.dart',
        'lib/performance/domain/performance_repository.dart',
        'lib/performance/domain/image_processor.dart',
        'lib/performance/domain/startup_optimizer.dart',
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
        'lib/performance/data/in_memory_performance_repository.dart',
        'lib/performance/data/in_memory_image_processor.dart',
        'lib/performance/data/in_memory_startup_optimizer.dart',
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
        'lib/performance/domain/lazy_load_config.dart',
        'lib/performance/domain/image_compression_config.dart',
        'lib/performance/domain/performance_metrics.dart',
        'lib/performance/domain/performance_repository.dart',
        'lib/performance/domain/image_processor.dart',
        'lib/performance/domain/startup_optimizer.dart',
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
        'lib/performance/data/in_memory_performance_repository.dart',
        'lib/performance/data/in_memory_image_processor.dart',
        'lib/performance/data/in_memory_startup_optimizer.dart',
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
        'lib/performance/domain/lazy_load_config.dart',
        'lib/performance/domain/image_compression_config.dart',
        'lib/performance/domain/performance_metrics.dart',
        'lib/performance/domain/startup_optimizer.dart',
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

    test('state files import no networking packages', () {
      final files = [
        'lib/state/domain/performance_state.dart',
        'lib/state/domain/performance_bloc.dart',
        'lib/state/data/local_performance_bloc.dart',
        'lib/state/ui/performance_monitor_screen.dart',
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

    test('state files contain no print or debugPrint', () {
      final files = [
        'lib/state/domain/performance_state.dart',
        'lib/state/domain/performance_bloc.dart',
        'lib/state/data/local_performance_bloc.dart',
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

    test('PerformanceMonitorScreen is wrapped in SecureScreenWrapper', () {
      final file = File('lib/state/ui/performance_monitor_screen.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      expect(
        source,
        contains('SecureScreenWrapper'),
        reason: 'PerformanceMonitorScreen must use SecureScreenWrapper',
      );
    });

    test('performance entities carry no identity fields', () {
      final files = [
        'lib/performance/domain/performance_metrics.dart',
        'lib/performance/domain/startup_optimizer.dart',
      ];
      final identityFields = [
        'phone',
        'email',
        'user_id',
        'blind_hash',
        'actorHash',
        'deviceId',
      ];

      for (final path in files) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        for (final field in identityFields) {
          final fieldPattern = RegExp(r'\b$field\b(?!\s*//)');
          final matches = fieldPattern.allMatches(source).toList();
          expect(
            matches,
            isEmpty,
            reason: '$path contains identity field: $field',
          );
        }
      }
    });
  });
}
