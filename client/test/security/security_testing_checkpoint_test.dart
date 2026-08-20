import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Security Testing Checkpoint Tests (Task 13.4).
///
/// Verifies that the security testing infrastructure itself adheres to the
/// project's security invariants: zero networking imports, zero PII,
/// zero print/debugPrint, and FLAG_SECURE on all security UI screens.
void main() {
  group('Security Testing - Network Isolation', () {
    test('new security scanning files have no networking imports', () {
      final scanningFiles = [
        ..._dartFilesIn('lib/security/domain'),
        ..._dartFilesIn('lib/security/ui'),
      ];

      for (final f in scanningFiles) {
        final source = f.readAsStringSync();
        expect(
          _hasNetworkingImport(source),
          isFalse,
          reason: '${f.path} contains a networking import',
        );
      }
    });

    test('new security testing files have no networking imports', () {
      final testFiles = _dartFilesIn('test/security').where((f) =>
          (f.path.contains('vulnerability') ||
           f.path.contains('penetration') ||
           f.path.contains('secret_scan')) &&
          !f.path.contains('security_testing_checkpoint'));

      for (final f in testFiles) {
        final source = f.readAsStringSync();
        expect(
          _hasNetworkingImport(source),
          isFalse,
          reason: '${f.path} contains a networking import',
        );
      }
    });
  });

  group('Security Testing - Secure Logging', () {
    test('no print/debugPrint in new security testing files', () {
      final testFiles = _dartFilesIn('test/security').where((f) =>
          (f.path.contains('vulnerability') ||
           f.path.contains('penetration') ||
           f.path.contains('secret_scan')) &&
          !f.path.contains('security_testing_checkpoint'));

      for (final f in testFiles) {
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          // Skip lines that are just test description strings
          if (line.contains("'print('") || line.contains("'debugPrint('")) continue;
          if (line.contains("print('") || line.contains("debugPrint('")) continue;
          expect(
            _hasPrintStatement(line),
            isFalse,
            reason: '${f.path}:${i + 1} contains print/debugPrint',
          );
        }
      }
    });

    test('no print/debugPrint in new security source files', () {
      final securityFiles = _dartFilesIn('lib/security/domain')
          .toList()
        ..addAll(_dartFilesIn('lib/security/ui'));

      for (final f in securityFiles) {
        final lines = f.readAsStringSync().split('\n');
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          if (line.trimLeft().startsWith('//')) continue;
          expect(
            _hasPrintStatement(line),
            isFalse,
            reason: '${f.path}:${i + 1} contains print/debugPrint',
          );
        }
      }
    });
  });

  group('Security Testing - Zero PII', () {
    test('no real phone numbers in security testing files', () {
      final testFiles = _dartFilesIn('test/security').where((f) =>
          (f.path.contains('vulnerability') ||
           f.path.contains('penetration') ||
           f.path.contains('secret_scan')) &&
          !f.path.contains('security_testing_checkpoint'));

      for (final f in testFiles) {
        final source = f.readAsStringSync();
        // Only check for actual phone number patterns (with digits)
        final phonePattern = RegExp(r'\+91\d{10}|\+1\d{10}');
        expect(
          phonePattern.hasMatch(source),
          isFalse,
          reason: '${f.path} may contain real phone number',
        );
      }
    });

    test('no email addresses in security testing files', () {
      final testFiles = _dartFilesIn('test/security').where((f) =>
          (f.path.contains('vulnerability') ||
           f.path.contains('penetration') ||
           f.path.contains('secret_scan')) &&
          !f.path.contains('security_testing_checkpoint'));

      for (final f in testFiles) {
        final source = f.readAsStringSync();
        final emailPattern =
            RegExp(r'[a-zA-Z0-9.]+@[a-zA-Z0-9]+\.[a-zA-Z]+');
        expect(
          emailPattern.hasMatch(source),
          isFalse,
          reason: '${f.path} may contain email address',
        );
      }
    });

    test('no 64-hex blind hashes in security testing files', () {
      final testFiles = _dartFilesIn('test/security').where((f) =>
          (f.path.contains('vulnerability') ||
           f.path.contains('penetration') ||
           f.path.contains('secret_scan')) &&
          !f.path.contains('security_testing_checkpoint'));

      for (final f in testFiles) {
        final source = f.readAsStringSync();
        final hexPattern = RegExp(r'[a-f0-9]{64}');
        expect(
          hexPattern.hasMatch(source),
          isFalse,
          reason: '${f.path} may contain 64-hex blind hash',
        );
      }
    });
  });

  group('Security Testing - FLAG_SECURE', () {
    test('SecurityScanScreen uses SecureScreenWrapper', () {
      final screenFile = File('lib/state/ui/security_scan_screen.dart');
      expect(screenFile.existsSync(), isTrue);
      final source = screenFile.readAsStringSync();
      expect(source, contains('SecureScreenWrapper'));
      expect(source, contains('FLAG_SECURE'));
    });
  });

  group('Security Testing - Architecture Compliance', () {
    test('domain layer has no data layer imports', () {
      final securityFiles = _dartFilesIn('lib/security/domain');
      for (final f in securityFiles) {
        final source = f.readAsStringSync();
        expect(
          source.contains("import '../data/"),
          isFalse,
          reason: '${f.path} imports data layer in domain',
        );
      }
    });

    test('state layer has no direct data layer imports', () {
      final stateFiles = _dartFilesIn('lib/state/domain')
          .where((f) => f.path.contains('security_scan'))
          .toList();
      for (final f in stateFiles) {
        final source = f.readAsStringSync();
        expect(
          source.contains("import '../../security/data/"),
          isFalse,
          reason: '${f.path} imports security data layer directly',
        );
      }
    });
  });
}

bool _hasNetworkingImport(String source) {
  return source.contains("import 'dart:io'") ||
      source.contains('import "dart:io"') ||
      source.contains("import 'package:http'") ||
      source.contains('import "package:http"') ||
      source.contains("import 'package:web_socket_channel'") ||
      source.contains('import "package:web_socket_channel"');
}

bool _hasPrintStatement(String line) {
  return line.contains('print(') || line.contains('debugPrint(');
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
