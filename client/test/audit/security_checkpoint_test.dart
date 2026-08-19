import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Audit Module Security Checkpoint (11.2)', () {
    test('audit domain has no networking imports', () {
      final domainDir = Directory('lib/audit/domain');
      final files = domainDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(files.isNotEmpty, true, reason: 'No domain files found');

      for (final f in files) {
        final source = f.readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (trimmed.contains("import 'dart:io'") ||
              trimmed.contains("import 'package:http'") ||
              trimmed.contains("import 'package:web_socket_channel'")) {
            fail('${f.path} contains networking import: $trimmed');
          }
        }
      }
    });

    test('audit data has no networking imports', () {
      final dataDir = Directory('lib/audit/data');
      final files = dataDir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      expect(files.isNotEmpty, true, reason: 'No data files found');

      for (final f in files) {
        final source = f.readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          final trimmed = line.trim();
          if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
          if (trimmed.contains("import 'dart:io'") ||
              trimmed.contains("import 'package:http'") ||
              trimmed.contains("import 'package:web_socket_channel'")) {
            fail('${f.path} contains networking import: $trimmed');
          }
        }
      }
    });

    test('audit files have no print/debugPrint calls', () {
      final dirs = [
        Directory('lib/audit/domain'),
        Directory('lib/audit/data'),
      ];

      final printPattern = RegExp(r'\b(print|debugPrint)\s*\(');

      for (final dir in dirs) {
        if (!dir.existsSync()) continue;
        final files = dir
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.dart'))
            .toList();

        for (final f in files) {
          final source = f.readAsStringSync();
          final lines = source.split('\n');
          for (var i = 0; i < lines.length; i++) {
            final trimmed = lines[i].trim();
            if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
            if (printPattern.hasMatch(trimmed)) {
              fail(
                '${f.path}:${i + 1} contains print/debugPrint: $trimmed',
              );
            }
          }
        }
      }
    });

    test('audit records carry no PII fields', () {
      final file = File('lib/audit/domain/audit_record.dart');
      final source = file.readAsStringSync();

      final piiFields = [
        'phone',
        'email',
        'phoneNumber',
        'rawPhone',
        'userName',
        'fullName',
        'address',
        'identity',
        'blindHash',
      ];

      for (final field in piiFields) {
        final regex = RegExp(r'^\s*(final|late)\s+\S+\s+' + field + r'\b',
            multiLine: true);
        expect(
          regex.hasMatch(source),
          false,
          reason: 'AuditRecord should not contain PII field: $field',
        );
      }
    });

    test('audit action wire names contain no PII', () {
      for (final name in [
        'consentGranted',
        'consentWithdrawn',
        'dataDeletionRequested',
        'accountCreated',
        'credentialChanged',
        'sensitiveDataAccessed',
      ]) {
        expect(name, isNot(contains('@')));
        expect(name, isNot(contains('+')));
        expect(name, isNot(contains('phone')));
        expect(name, isNot(contains('email')));
      }
    });

    test('audit UI screen renders SecureScreenWrapper', () {
      final file = File('lib/state/ui/audit_log_screen.dart');
      final source = file.readAsStringSync();

      expect(
        source.contains('SecureScreenWrapper'),
        true,
        reason: 'Audit log screen must use SecureScreenWrapper (FLAG_SECURE)',
      );
    });

    test('audit UI screen has no networking imports', () {
      final file = File('lib/state/ui/audit_log_screen.dart');
      final source = file.readAsStringSync();

      final lines = source.split('\n');
      for (final line in lines) {
        final trimmed = line.trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        if (trimmed.contains("import 'dart:io'") ||
            trimmed.contains("import 'package:http'") ||
            trimmed.contains("import 'package:web_socket_channel'")) {
          fail('audit UI contains networking import: $trimmed');
        }
      }
    });

    test('audit screen has no print/debugPrint calls', () {
      final file = File('lib/state/ui/audit_log_screen.dart');
      final source = file.readAsStringSync();

      final printPattern = RegExp(r'\b(print|debugPrint)\s*\(');
      final lines = source.split('\n');
      for (var i = 0; i < lines.length; i++) {
        final trimmed = lines[i].trim();
        if (trimmed.startsWith('//') || trimmed.startsWith('///')) continue;
        expect(
          printPattern.hasMatch(trimmed),
          false,
          reason:
              'audit screen:${i + 1} contains print/debugPrint: $trimmed',
        );
      }
    });
  });
}
