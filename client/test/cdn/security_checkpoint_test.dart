import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regex for detecting forbidden networking imports.
  final networkingImport = RegExp(
    "import\\s+['\"](?:dart:io|package:http|package:web_socket_channel)",
  );

  final printPattern = RegExp(r'\b(?:print|debugPrint)\s*\(');

  group('CDN Module Security Checkpoint - Task 12.3', () {
    test('domain files import no networking packages', () {
      final files = [
        'lib/cdn/domain/cdn_config.dart',
        'lib/cdn/domain/edge_cache_rule.dart',
        'lib/cdn/domain/delivery_metrics.dart',
        'lib/cdn/domain/cdn_repository.dart',
        'lib/cdn/domain/cdn_fetcher.dart',
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

    test('data files contain no print or debugPrint', () {
      final files = [
        'lib/cdn/data/in_memory_cdn_repository.dart',
        'lib/cdn/data/in_memory_cdn_fetcher.dart',
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

    test('domain files contain no print or debugPrint', () {
      final files = [
        'lib/cdn/domain/cdn_config.dart',
        'lib/cdn/domain/edge_cache_rule.dart',
        'lib/cdn/domain/delivery_metrics.dart',
        'lib/cdn/domain/cdn_repository.dart',
        'lib/cdn/domain/cdn_fetcher.dart',
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
        'lib/cdn/domain/cdn_config.dart',
        'lib/cdn/domain/edge_cache_rule.dart',
        'lib/cdn/domain/delivery_metrics.dart',
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

    test('CdnDeliveryScreen is wrapped in SecureScreenWrapper', () {
      final file = File('lib/state/ui/cdn_delivery_screen.dart');
      if (!file.existsSync()) return;
      final source = file.readAsStringSync();
      expect(
        source,
        contains('SecureScreenWrapper'),
        reason: 'CdnDeliveryScreen must use SecureScreenWrapper (FLAG_SECURE)',
      );
    });

    test('state files import no networking packages', () {
      final files = [
        'lib/state/domain/cdn_delivery_state.dart',
        'lib/state/domain/cdn_delivery_bloc.dart',
        'lib/state/data/local_cdn_delivery_bloc.dart',
        'lib/state/ui/cdn_delivery_screen.dart',
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
        'lib/state/domain/cdn_delivery_state.dart',
        'lib/state/domain/cdn_delivery_bloc.dart',
        'lib/state/data/local_cdn_delivery_bloc.dart',
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

    test('CDN entities carry no identity fields', () {
      final files = [
        'lib/cdn/domain/delivery_metrics.dart',
        'lib/cdn/domain/edge_cache_rule.dart',
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
