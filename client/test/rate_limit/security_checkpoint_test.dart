import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Rate Limiting Security Checkpoint (11.3)', () {
    test('no networking imports in rate_limit domain', () {
      final domainFiles = _dartFilesIn('lib/rate_limit/domain');
      for (final f in domainFiles) {
        final source = f.readAsStringSync();
        expect(
          source.contains("import 'dart:io'") ||
              source.contains('import "dart:io"') ||
              source.contains("import 'package:http'") ||
              source.contains('import "package:http"') ||
              source.contains("import 'package:web_socket_channel'") ||
              source.contains('import "package:web_socket_channel"'),
          isFalse,
          reason: '${f.path} contains a networking import',
        );
      }
    });

    test('no networking imports in rate_limit data', () {
      final dataFiles = _dartFilesIn('lib/rate_limit/data');
      for (final f in dataFiles) {
        final source = f.readAsStringSync();
        expect(
          source.contains("import 'dart:io'") ||
              source.contains('import "dart:io"') ||
              source.contains("import 'package:http'") ||
              source.contains('import "package:http"') ||
              source.contains("import 'package:web_socket_channel'") ||
              source.contains('import "package:web_socket_channel"'),
          isFalse,
          reason: '${f.path} contains a networking import',
        );
      }
    });

    test('no print/debugPrint in rate_limit production files', () {
      final files = _dartFilesIn('lib/rate_limit');
      for (final f in files) {
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Skip comments and doc comments
          if (line.trimLeft().startsWith('//')) continue;
          expect(
            line.contains('print(') || line.contains('debugPrint('),
            isFalse,
            reason: '${f.path}:${i + 1} contains print/debugPrint',
          );
        }
      }
    });

    test('no print/debugPrint in state rate_limit files', () {
      final files = [
        File('lib/state/domain/rate_limit_state.dart'),
        File('lib/state/domain/rate_limit_bloc.dart'),
        File('lib/state/data/local_rate_limit_bloc.dart'),
      ];
      for (final f in files) {
        if (!f.existsSync()) continue;
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          expect(
            line.contains('print(') || line.contains('debugPrint('),
            isFalse,
            reason: '${f.path}:${i + 1} contains print/debugPrint',
          );
        }
      }
    });

    test('no identity fields in rate limit entities', () {
      final domainFiles = _dartFilesIn('lib/rate_limit/domain');
      for (final f in domainFiles) {
        final source = f.readAsStringSync();
        final lines = source.split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          if (line.trimLeft().startsWith('///')) continue;
          final lower = line.toLowerCase();
          // Check for actual identity data fields (not enum value names like usernameClaim)
          expect(
            lower.contains('phone') ||
                lower.contains('email') ||
                lower.contains('blind_hash') ||
                lower.contains('userid'),
            isFalse,
            reason: '${f.path}:${i + 1} may contain identity fields',
          );
        }
      }
    });

    test('schema tables have zero identity columns', () {
      final schemaFile = File('lib/database/domain/schema.dart');
      final source = schemaFile.readAsStringSync();

      expect(source, contains('rate_limit_buckets'));
      expect(source, contains('abuse_events'));

      // Verify no identity-like columns in rate_limit tables
      final rateLimitSection = source.substring(
        source.indexOf('rateLimitBuckets'),
        source.indexOf('abuseEvents') + 200,
      );
      final identityColumns = ['phone', 'email', 'user_id', 'blind_hash'];
      for (final col in identityColumns) {
        expect(
          rateLimitSection.toLowerCase(),
          isNot(contains(col.toLowerCase())),
          reason: 'rate_limit table should not contain $col column',
        );
      }
    });

    test('FLAG_SECURE present on RateLimitScreen', () {
      final screenFile = File('lib/state/ui/rate_limit_screen.dart');
      final source = screenFile.readAsStringSync();
      expect(source, contains('SecureScreenWrapper'));
    });

    test('rate limit UI has no networking imports', () {
      final screenFile = File('lib/state/ui/rate_limit_screen.dart');
      final source = screenFile.readAsStringSync();
      expect(
        source.contains("import 'dart:io'") ||
            source.contains('import "dart:io"') ||
            source.contains("import 'package:http'") ||
            source.contains('import "package:http"') ||
            source.contains("import 'package:web_socket_channel'") ||
            source.contains('import "package:web_socket_channel"'),
        isFalse,
        reason: 'rate_limit_screen.dart contains a networking import',
      );
    });
  });
}

List<File> _dartFilesIn(String dir) {
  final directory = Directory(dir);
  if (!directory.existsSync()) return [];
  return directory
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}
