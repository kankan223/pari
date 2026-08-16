import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Phase 9 foundation SECURITY CHECKPOINT (Task 8.8 scaffold).
///
/// 1. The Academy domain/data/state layers import NO networking
///    (http/WebSocket/dart:io sockets) — local-first by construction.
/// 2. No raw debug output (print/logger) exists in Academy production code.
/// 3. No PII-shaped literals (E.164 phones, 64-hex blind hashes, emails)
///    exist in Academy production code.
/// 4. The Academy UI surface is wrapped in FLAG_SECURE (verified by the
///    masthead widget test; the scaffold ships one entry-point component).
void main() {
  group('Phase 9 SECURITY CHECKPOINT (Task 8.8 scaffold)', () {
    test('Academy production code imports no networking packages', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();
      expect(files, isNotEmpty, reason: 'academy tree must exist');

      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        if (forbidden.hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in lib/academy');
    });

    test('Academy production code never prints', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        if (printPattern.hasMatch(source)) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in lib/academy');
    });

    test('Academy production code contains no PII-shaped literals', () {
      final libDir = Directory('lib/academy');
      final files = libDir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .toList();

      // E.164 phone / 64-hex blind hash / email shapes.
      final piiPatterns = [
        RegExp(r'\+?\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in files) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in lib/academy');
    });
    test('Academy state declares no identity-typed fields', () async {
      // Structural proof: the state projection declares no identity-typed
      // fields — only syllabus content, module-id sets, and the generic
      // error string. (The value objects themselves are zero-identity by
      // construction — validated in academy_module_test.dart.)
      final stateFile =
          File('lib/state/domain/academy_state.dart').readAsStringSync();
      // Field declarations only — the security doc comment may mention
      // the words "phone"/"email", which is not a leak.
      final declared = RegExp(r'final\s+[\w<>]+\s+(\w+);')
          .allMatches(stateFile)
          .map((m) => m.group(1)!.toLowerCase())
          .toList();
      expect(declared, isNot(contains('phone')));
      expect(declared, isNot(contains('email')));
      expect(declared, isNot(contains('blindHash')));
      expect(declared, isNot(contains('name')));
    });
  });
}
