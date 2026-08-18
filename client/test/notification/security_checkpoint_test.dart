import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Notification System security checkpoint (Task 10.4)', () {
    test('notification domain and data files have no networking imports', () {
      final files = _notificationFiles();
      expect(files, isNotEmpty);

      final forbidden = RegExp(
        r'''import\s+['"](?:dart:io|package:http|package:web_socket_channel)''',
      );

      for (final f in files) {
        final source = f.readAsStringSync();
        // Check only non-comment lines.
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

    test('notification files have no print/debugPrint calls', () {
      final files = _notificationFiles();
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

    test('notification UI screens have no PII literals', () {
      final files = _uiFiles();
      expect(files, isNotEmpty);

      // Patterns that look like PII: phone numbers, emails, 64-hex hashes.
      final piiPatterns = [
        RegExp(r'\+\d{10,15}'), // phone with country code
        RegExp(r'\b\d{10}\b'), // 10-digit phone
        RegExp(r'[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}'), // email
        RegExp(r'[0-9a-f]{64}'), // 64-hex blind hash
      ];

      for (final f in files) {
        final source = f.readAsStringSync();
        // Strip comments.
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

    test('notification UI files have no networking imports', () {
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

    test('widget tree scan: notification history screen has no raw hashes',
        () {
      final screenFile =
          File('lib/state/ui/notification_history_screen.dart');
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

    test('widget tree scan: notification preferences screen has no raw hashes',
        () {
      final screenFile =
          File('lib/state/ui/notification_preferences_screen.dart');
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

List<File> _notificationFiles() {
  final dirs = ['lib/notification/domain', 'lib/notification/data'];
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
      .where((f) => f.path.contains('notification'))
      .toList();
}
