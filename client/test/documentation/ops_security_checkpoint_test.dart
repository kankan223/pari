import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Operations Documentation Security Checkpoint', () {
    List<String> _opsDomainFiles() {
      final dir = Directory('lib/documentation/domain');
      if (!dir.existsSync()) return [];
      return dir
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .map((f) => f.path)
          .toList()
        ..sort();
    }

    test('no networking imports in ops documentation domain files', () {
      final files = _opsDomainFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('dart:io') && !source.contains('// dart:io'),
          isFalse,
          reason: '$path may contain dart:io import',
        );
        expect(
          source.contains('package:http') &&
              !source.contains('// package:http'),
          isFalse,
          reason: '$path may contain package:http import',
        );
        expect(
          source.contains('package:web_socket_channel') &&
              !source.contains('// package:web_socket_channel'),
          isFalse,
          reason: '$path may contain web_socket_channel import',
        );
      }
    });

    test('no print or debugPrint in ops documentation source files', () {
      final files = _opsDomainFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          expect(
            line.contains('print(') || line.contains('debugPrint('),
            isFalse,
            reason: '$path contains print/debugPrint: $line',
          );
        }
      }
    });

    test('no PII patterns in ops documentation domain files', () {
      final files = _opsDomainFiles();
      expect(files, isNotEmpty);
      final phonePattern = RegExp(r'\+\d{10,15}');
      final emailPattern = RegExp(r'\S+@\S+\.\S+');
      final roleBasedPattern =
          RegExp(r'(privacy|support|admin|help|contact|noreply)@');
      final hex64Pattern = RegExp(r'\b[0-9a-fA-F]{64}\b');
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final codeLines = source
            .split('\n')
            .where((l) => !l.trimLeft().startsWith('//'))
            .join('\n');
        expect(
          phonePattern.hasMatch(codeLines),
          isFalse,
          reason: '$path contains phone number pattern',
        );
        final codeWithoutRoleEmails =
            codeLines.replaceAll(roleBasedPattern, '');
        expect(
          emailPattern.hasMatch(codeWithoutRoleEmails),
          isFalse,
          reason: '$path contains personal email pattern',
        );
        expect(
          hex64Pattern.hasMatch(codeLines),
          isFalse,
          reason: '$path contains 64-hex hash pattern',
        );
      }
    });

    test('no hardcoded secrets in ops documentation domain files', () {
      final files = _opsDomainFiles();
      expect(files, isNotEmpty);
      // Use simple contains-based checks instead of complex regex
      final secretKeywords = [
        'password=',
        'api_key=',
        'secret=',
        'token=',
        'password :',
        'api_key :',
        'secret :',
        'token :',
      ];
      for (final path in files) {
        final source = File(path).readAsStringSync();
        final lines = source.split('\n');
        for (final line in lines) {
          if (line.trimLeft().startsWith('//')) continue;
          final lower = line.toLowerCase();
          for (final keyword in secretKeywords) {
            expect(
              lower.contains(keyword),
              isFalse,
              reason: '$path may contain hardcoded secret keyword: $line',
            );
          }
        }
      }
    });

    test('all domain files follow clean architecture', () {
      final files = _opsDomainFiles();
      expect(files, isNotEmpty);
      for (final path in files) {
        final source = File(path).readAsStringSync();
        expect(
          source.contains('package:civic_commons/repository/'),
          isFalse,
          reason: '$path imports repository layer',
        );
        expect(
          source.contains('package:civic_commons/state/'),
          isFalse,
          reason: '$path imports state layer',
        );
      }
    });

    test('operations documentation test files have zero networking', () {
      // Note: this checkpoint test itself imports dart:io for file scanning,
      // so it is excluded from the networking check.
      final testFiles = [
        'test/documentation/deployment_guide_test.dart',
        'test/documentation/runbook_test.dart',
        'test/documentation/troubleshooting_guide_test.dart',
        'test/documentation/infrastructure_doc_test.dart',
      ];
      for (final path in testFiles) {
        final file = File(path);
        if (!file.existsSync()) continue;
        final source = file.readAsStringSync();
        final importLines = source
            .split('\n')
            .where((l) => l.trimLeft().startsWith('import '))
            .join('\n');
        expect(
          importLines.contains('dart:io'),
          isFalse,
          reason: '$path test file contains dart:io import',
        );
        expect(
          importLines.contains('package:http'),
          isFalse,
          reason: '$path test file contains package:http import',
        );
        expect(
          importLines.contains('package:web_socket_channel'),
          isFalse,
          reason: '$path test file contains web_socket_channel import',
        );
      }
    });
  });
}
