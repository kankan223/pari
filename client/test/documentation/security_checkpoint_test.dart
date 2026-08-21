import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Phase 15.1 Security Checkpoint', () {
    List<String> documentationFiles() {
      final dir = Directory('lib/documentation');
      if (!dir.existsSync()) return [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList();
    }

    List<String> documentationTestFiles() {
      final dir = Directory('test/documentation');
      if (!dir.existsSync()) return [];
      return dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList();
    }

    test('documentation source files have zero networking imports', () {
      final files = documentationFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('dart:io')));
        expect(source, isNot(contains('package:http')));
        expect(source, isNot(contains('package:web_socket_channel')));
      }
    });

    test('documentation source files have zero print/debugPrint', () {
      final files = documentationFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          expect(line, isNot(contains('print(')));
          expect(line, isNot(contains('debugPrint(')));
        }
      }
    });

    test('documentation source files have zero phone/email PII', () {
      final files = documentationFiles();
      expect(files, isNotEmpty);
      final phonePattern = RegExp(r'\+[0-9]{10}');
      final emailPattern =
          RegExp(r'[a-zA-Z0-9._-]+@[a-zA-Z0-9._-]+\.[a-zA-Z]');
      // Role-based emails (privacy@, support@, etc.) are not PII.
      final roleBasedPattern =
          RegExp(r'(privacy|support|admin|help|contact|noreply)@');
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final code = source
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        expect(
          phonePattern.hasMatch(code),
          isFalse,
          reason: '$path contains phone pattern',
        );
        // Filter out role-based emails before checking for PII.
        final codeWithoutRoleEmails =
            code.replaceAll(roleBasedPattern, '');
        expect(
          emailPattern.hasMatch(codeWithoutRoleEmails),
          isFalse,
          reason: '$path contains personal email pattern',
        );
      }
    });

    test('documentation source files have zero 64-hex blind hash literals', () {
      final files = documentationFiles();
      expect(files, isNotEmpty);
      final hex64 = RegExp(r'[0-9a-f]{64}');
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final code = source
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');
        final matches = hex64.allMatches(code).toList();
        expect(
          matches,
          isEmpty,
          reason: '$path contains 64-hex hash literal',
        );
      }
    });

    test('documentation test files have zero print/debugPrint', () {
      final files = documentationTestFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        if (path.contains('security_checkpoint_test')) continue;
        final source = File(path).readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          expect(line, isNot(contains('print(')));
          expect(line, isNot(contains('debugPrint(')));
        }
      }
    });

    test('no hardcoded secrets in documentation domain', () {
      final files = documentationFiles();
      expect(files, isNotEmpty);
      final secretWords = ['password', 'api_key', 'secret', 'token'];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          for (final word in secretWords) {
            if (line.contains('$word =') || line.contains('$word:')) {
              expect(
                line,
                isNot(contains('"')),
                reason: '$path may contain hardcoded secret: $word',
              );
            }
          }
        }
      }
    });

    test('documentation test files have zero networking imports', () {
      final files = documentationTestFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        if (path.contains('security_checkpoint_test')) continue;
        final source = File(path).readAsStringSync();
        expect(source, isNot(contains('dart:io')));
        expect(source, isNot(contains('package:http')));
        expect(source, isNot(contains('package:web_socket_channel')));
      }
    });
  });
}
