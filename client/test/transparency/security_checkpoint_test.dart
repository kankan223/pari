import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Transparency Log security checkpoint (Task 10.5)', () {
    test('transparency domain and data files have no networking imports', () {
      final files = _transparencyFiles();
      expect(files, isNotEmpty);

      final forbidden = RegExp(
        r'''import\s+['"](?:dart:io|package:http|package:web_socket_channel)''',
      );

      for (final f in files) {
        final source = f.readAsStringSync();
        final codeLines = source.split('\n').where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('///') && !trimmed.startsWith('//');
        });
        for (final line in codeLines) {
          expect(
            forbidden.hasMatch(line),
            false,
            reason: '${f.path} contains networking import: $line',
          );
        }
      }
    });

    test('transparency files have no print/debugPrint calls', () {
      final files = _transparencyFiles();
      final printPattern = RegExp(r'\b(?:print|debugPrint)\s*\(');

      for (final f in files) {
        final source = f.readAsStringSync();
        final codeLines = source.split('\n').where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('///') && !trimmed.startsWith('//');
        });
        for (final line in codeLines) {
          expect(
            printPattern.hasMatch(line),
            false,
            reason: '${f.path} contains print/debugPrint: $line',
          );
        }
      }
    });

    test('transparency UI screen has no PII literals', () {
      final files = _uiFiles();
      expect(files, isNotEmpty);

      final piiPatterns = [
        RegExp(r'\+\d{10,15}'), // phone with country code
        RegExp(r'\b\d{10}\b'), // 10-digit phone
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'),
        RegExp(r'[0-9a-f]{64}'), // 64-hex blind hash
      ];

      for (final f in files) {
        final source = f.readAsStringSync();
        final code = source
            .split('\n')
            .where((line) => !line.trimLeft().startsWith('///'))
            .where((line) => !line.trimLeft().startsWith('//'))
            .join('\n');

        for (final pattern in piiPatterns) {
          final match = pattern.firstMatch(code);
          expect(
            match,
            isNull,
            reason:
                '${f.path} contains PII pattern ${pattern.pattern}: ${match?.group(0)}',
          );
        }
      }
    });

    test('transparency UI files have no networking imports', () {
      final files = _uiFiles();
      final forbidden = RegExp(
        r'''import\s+['"](?:dart:io|package:http|package:web_socket_channel)''',
      );

      for (final f in files) {
        final source = f.readAsStringSync();
        final codeLines = source.split('\n').where((line) {
          final trimmed = line.trimLeft();
          return !trimmed.startsWith('///') && !trimmed.startsWith('//');
        });
        for (final line in codeLines) {
          expect(
            forbidden.hasMatch(line),
            false,
            reason: '${f.path} contains networking import: $line',
          );
        }
      }
    });

    test('widget tree scan: transparency log screen has no raw hashes', () {
      final screenFile = File('lib/state/ui/transparency_log_screen.dart');
      final source = screenFile.readAsStringSync();

      // Strip comments before checking for PII.
      final code = source
          .split('\n')
          .where((line) => !line.trimLeft().startsWith('///'))
          .where((line) => !line.trimLeft().startsWith('//'))
          .join('\n');

      expect(code.contains('actorHash'), false);
      expect(code.contains('blindHash'), false);
      expect(code.contains('phone'), false);
    });
  });
}

List<File> _transparencyFiles() {
  final dirs = ['lib/transparency/domain', 'lib/transparency/data'];
  final files = <File>[];
  for (final dir in dirs) {
    final d = Directory(dir);
    if (d.existsSync()) {
      for (final f in d.listSync().whereType<File>()) {
        if (f.path.endsWith('.dart')) files.add(f);
      }
    }
  }
  return files;
}

List<File> _uiFiles() {
  final dir = Directory('lib/state/ui');
  if (!dir.existsSync()) return [];
  return dir
      .listSync()
      .whereType<File>()
      .where((f) => f.path.contains('transparency'))
      .toList();
}
