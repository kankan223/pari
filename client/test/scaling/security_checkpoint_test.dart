import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regex for detecting forbidden networking imports.
  final networkingImport = RegExp(
    "import\\s+['\"](?:dart:io|package:http|package:web_socket_channel)",
  );

  final printPattern = RegExp(r'\b(?:print|debugPrint)\s*\(');

  group('Scaling Module Security Checkpoint - Task 12.4', () {
    test('domain files import no networking packages', () {
      final files = [
        'lib/scaling/domain/load_test_scenario.dart',
        'lib/scaling/domain/connection_pool_config.dart',
        'lib/scaling/domain/shard_router.dart',
        'lib/scaling/domain/scaling_metrics.dart',
        'lib/scaling/domain/scaling_repository.dart',
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
        'lib/scaling/domain/load_test_scenario.dart',
        'lib/scaling/domain/connection_pool_config.dart',
        'lib/scaling/domain/shard_router.dart',
        'lib/scaling/domain/scaling_metrics.dart',
        'lib/scaling/domain/scaling_repository.dart',
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
        'lib/scaling/domain/load_test_scenario.dart',
        'lib/scaling/domain/connection_pool_config.dart',
        'lib/scaling/domain/shard_router.dart',
        'lib/scaling/domain/scaling_metrics.dart',
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

    test('ScalingMonitorScreen is wrapped in SecureScreenWrapper', () {
      final file = File('lib/state/ui/scaling_monitor_screen.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      expect(
        source,
        contains('SecureScreenWrapper'),
        reason:
            'ScalingMonitorScreen must use SecureScreenWrapper (FLAG_SECURE)',
      );
    });

    test('state files import no networking packages', () {
      final files = [
        'lib/state/domain/scaling_state.dart',
        'lib/state/domain/scaling_bloc.dart',
        'lib/state/data/local_scaling_bloc.dart',
        'lib/state/ui/scaling_monitor_screen.dart',
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
        'lib/state/domain/scaling_state.dart',
        'lib/state/domain/scaling_bloc.dart',
        'lib/state/data/local_scaling_bloc.dart',
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

    test('scaling entities carry no identity fields', () {
      final files = [
        'lib/scaling/domain/scaling_metrics.dart',
        'lib/scaling/domain/shard_router.dart',
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

    test('shard definitions carry no PII fields', () {
      final file = File('lib/scaling/domain/shard_router.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      // Shards carry ONLY region names + pin prefixes (public civic data)
      expect(source, isNot(contains('phone')));
      expect(source, isNot(contains('email')));
      expect(source, isNot(contains('user_name')));
    });
  });
}
