import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 3.5): the state layer never exposes raw
/// decrypted data in logs — no print()/debugPrint() of payloads anywhere in
/// lib/state, and the BLoC state models carry only UI-safe projections.
///
/// NOTE: sensitive tokens may appear inside docstring security notes (e.g.
/// "excludes [Message.ciphertext]") — those are documentation, not fields.
/// Scans strip comments so only DECLARATIONS/imports are verified.
void main() {
  final stateFiles = _dartFilesUnder('lib/state');

  group('SECURITY CHECKPOINT - BLoC never exposes raw decrypted data', () {
    test('lib/state contains no print() or debugPrint() of payload data', () {
      expect(stateFiles, isNotEmpty,
          reason: 'lib/state must contain source files');

      for (final file in stateFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print raw data');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint raw data');
      }
    });

    test('conversation state model exposes no ciphertext/session bytes', () {
      final source = _codeOnly(
          File('lib/state/domain/conversation_state.dart').readAsStringSync());

      // The projection declares only id + participantHash.
      expect(source, contains('class ConversationSummary'));
      expect(source, isNot(contains('Uint8List')));
      expect(source, isNot(contains('encryptedSessionState')));
      expect(source, isNot(contains('final Uint8List')));
    });

    test('message state model exposes no ciphertext/plaintext fields', () {
      final source = _codeOnly(
          File('lib/state/domain/message_state.dart').readAsStringSync());

      expect(source, contains('class MessageSummary'));
      expect(source, isNot(contains('Uint8List')));
      expect(source, isNot(contains('ciphertext')));
      expect(source, isNot(contains('plaintext')));
      expect(source, isNot(contains('decrypted')));
    });

    test('sync status state exposes only the enum + integer count', () {
      final source = _codeOnly(
          File('lib/state/domain/sync_status_bloc.dart').readAsStringSync());

      expect(source, contains('class SyncStatusState'));
      expect(source, contains('final SyncStatus status'));
      expect(source, contains('final int pendingCount'));
      expect(source, isNot(contains('String')));
      expect(source, isNot(contains('Uint8List')));
      expect(source, isNot(contains('payload')));
      expect(source, isNot(contains('hash')));
    });

    test('no raw sensitive fields are declared in any state model', () {
      const sensitiveTokens = [
        'ciphertext',
        'plaintext',
        'decrypted',
        'sessionKey',
        'rawPayload',
        'Uint8List',
      ];

      for (final file in stateFiles) {
        if (!file.endsWith('_state.dart') &&
            !file.endsWith('_bloc.dart') &&
            !file.endsWith('sync_status.dart')) {
          continue;
        }
        final source =
            _codeOnly(File(file).readAsStringSync());
        for (final token in sensitiveTokens) {
          expect(source.contains(token), isFalse,
              reason: '$file must not declare raw data field "$token"');
        }
      }
    });

    test('BLoCs depend on abstract interfaces, not concrete transports', () {
      final blocFiles = stateFiles.where((p) => p.endsWith('_bloc.dart'));

      for (final file in blocFiles) {
        final source = File(file).readAsStringSync();
        // No direct network/HTTP anywhere in the state layer.
        expect(source.contains('package:http'), isFalse,
            reason: '$file must not import HTTP');
        expect(source.contains('dart:io'), isFalse,
            reason: '$file must not import dart:io');
        expect(source.contains('sqflite'), isFalse,
            reason: '$file must not touch the database directly');
      }
    });
  });
}

/// Returns [source] with comment lines (docstrings and //-comments) removed,
/// so sensitive-token scans only inspect declarations and imports.
String _codeOnly(String source) {
  final lines = source.split('\n');
  final code = <String>[];
  for (final line in lines) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('///') ||
        trimmed.startsWith('//') ||
        trimmed.startsWith('/*') ||
        trimmed.startsWith('*')) {
      continue;
    }
    code.add(line);
  }
  return code.join('\n');
}

List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    return [];
  }
  return root
      .listSync(recursive: true)
      .whereType<File>()
      .map((f) => f.path)
      .where((p) => p.endsWith('.dart'))
      .toList();
}
