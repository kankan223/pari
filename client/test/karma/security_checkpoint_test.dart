import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 10.2 SECURITY CHECKPOINT — Civic Karma Engine.
///
/// 1. The karma surface (domain + data + state + UI) imports NO networking
///    (http/WebSocket/dart:io sockets) — the ledger is local-first by
///    construction.
/// 2. No raw debug output (print/logger) exists in karma production code.
/// 3. No PII-shaped literals (E.164 phones, 64-hex blind hashes, emails)
///    exist in karma production code — the actor is a runtime value, never
///    a literal.
/// 4. Karma events are APPEND-ONLY + AUDITABLE — the schema table carries
///    the SHA-256 chain-link columns and zero identity columns (verified in
///    the database suite; the repository enforces chain integrity).
/// 5. The UI surface renders only fixed labels + the public balance — never
///    the actor hash (verified by the widget test).
void main() {
  group('Task 10.2 SECURITY CHECKPOINT — Civic Karma Engine', () {
    const karmaFiles = [
      'lib/karma/domain/karma_action.dart',
      'lib/karma/domain/karma_event.dart',
      'lib/karma/domain/karma_gate.dart',
      'lib/karma/domain/karma_calculation.dart',
      'lib/karma/domain/karma_decay.dart',
      'lib/karma/domain/lockstep_detector.dart',
      'lib/karma/domain/karma_repository.dart',
      'lib/karma/domain/karma_event_source.dart',
      'lib/karma/data/karma_event_records.dart',
      'lib/karma/data/local_karma_repository.dart',
      'lib/karma/data/in_memory_karma_event_source.dart',
      'lib/state/domain/karma_state.dart',
      'lib/state/domain/karma_bloc.dart',
      'lib/state/data/local_karma_bloc.dart',
      'lib/state/ui/karma_status_screen.dart',
    ];

    List<File> files() =>
        karmaFiles.map(File.new).where((f) => f.existsSync()).toList();

    test('karma production code imports no networking packages', () {
      final list = files();
      expect(list, isNotEmpty, reason: 'karma tree must exist');

      final forbidden = RegExp(
        "import\\s+['\\\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in list) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the karma layer');
    });

    test('karma production code never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in files()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the karma layer');
    });

    test('karma production code contains no PII-shaped literals', () {
      // E.164 phone / 64-hex blind hash / email shapes.
      final piiPatterns = [
        RegExp(r'\+\d{10,15}'),
        RegExp(r'\b[0-9a-f]{64}\b'),
        RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+'),
      ];
      final offenders = <String>[];
      for (final f in files()) {
        final source = f.readAsStringSync();
        for (final p in piiPatterns) {
          if (p.hasMatch(source)) {
            offenders.add(f.path);
            break;
          }
        }
      }
      expect(offenders, isEmpty,
          reason: 'no PII-shaped literals in the karma layer');
    });

    test('the karma UI never references the actor hash field', () {
      final screen = File('lib/state/ui/karma_status_screen.dart');
      expect(screen.existsSync(), isTrue);
      final source = screen.readAsStringSync();
      expect(source.contains('actorHash'), isFalse,
          reason: 'the screen must not reach into event actor hashes');
      expect(source.contains('blindHash'), isFalse,
          reason: 'the screen must not reference blind hashes');
    });

    test('the karma state carries no actor/identity fields', () {
      final stateFile = File('lib/state/domain/karma_state.dart');
      final source = stateFile.readAsStringSync();
      expect(source.contains('actorHash'), isFalse);
      expect(source.contains('blindHash'), isFalse);
      expect(source.contains('eventId'), isFalse);
      expect(source.contains('phone'), isFalse);
    });

    test('the karma domain has no decryption/identity crypto primitives', () {
      // The ledger only HASHES (SHA-256 chain links) — it never encrypts,
      // decrypts, or signs identity.
      for (final f in files()) {
        final source = f.readAsStringSync();
        expect(source.contains('decrypt'), isFalse,
            reason: '${f.path} must not decrypt');
        expect(source.contains('AesGcm'), isFalse,
            reason: '${f.path} must not build AEAD ciphers');
        expect(source.contains('ed25519'), isFalse,
            reason: '${f.path} must not sign identity');
      }
    });
  });
}
