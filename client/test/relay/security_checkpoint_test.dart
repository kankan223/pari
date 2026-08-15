import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 6.4): the relay client is the ONLY WebSocket
/// transport in the app, and it must uphold the zero-PII invariants:
///  - The access token lives ONLY in the first auth frame body — never in a
///    URL (query strings are logged by proxies).
///  - Envelope ciphertext is opaque and never logged.
///  - No raw debug output (print) anywhere in lib/relay.
///  - No PII-shaped literal data in the source (phone/e-mail shapes).
void main() {
  final relayFiles = _dartFilesUnder('lib/relay');

  group('SECURITY CHECKPOINT - relay is a privacy-safe byte carrier', () {
    test('lib/relay exists and contains the transport implementation', () {
      expect(relayFiles, isNotEmpty);
      expect(relayFiles.any((f) => f.contains('relay_client.dart')), isTrue);
      expect(
        relayFiles.any((f) => f.contains('web_socket_relay_socket.dart')),
        isTrue,
      );
    });
    test('no URL builder ever embeds the access token', () {
      for (final file in relayFiles) {
        final source = File(file).readAsStringSync();
        // Only scan CODE lines (comment/doc text about the invariant is
        // expected and harmless). The token must never be spliced into a
        // URL string or appended as a query parameter.
        for (final line in _codeLines(source)) {
          expect(
            line.contains('?token=') ||
                line.contains('?access_token=') ||
                line.contains('&access_token='),
            isFalse,
            reason: '$file must never append the token as a query parameter',
          );
        }
      }
    });

    test('no raw debug output anywhere in lib/relay', () {
      for (final file in relayFiles) {
        final source = File(file).readAsStringSync();
        for (final line in _codeLines(source)) {
          expect(
            line.contains('print(') ||
                line.contains('debugPrint(') ||
                line.contains('println('),
            isFalse,
            reason: '$file must not print — output could leak frame payloads',
          );
        }
      }
    });
    test('no PII-shaped literals (phones / e-mails) in lib/relay', () {
      final phoneShape = RegExp("['\"][+]?\\d{8,15}['\"]");
      final emailShape =
          RegExp("['\"][a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}['\"]");
      for (final file in relayFiles) {
        final source = File(file).readAsStringSync();
        for (final line in _codeLines(source)) {
          expect(phoneShape.hasMatch(line), isFalse,
              reason: '$file contains a phone-shaped literal');
          expect(emailShape.hasMatch(line), isFalse,
              reason: '$file contains an email-shaped literal');
        }
      }
    });

    test('ciphertext is never logged and never leaves as text', () {
      for (final file in relayFiles) {
        final source = File(file).readAsStringSync();
        // The codec base64-encodes for the wire (required), but nothing may
        // stringify or log the raw bytes or decoded text.
        for (final line in _codeLines(source)) {
          expect(
            RegExp('log.*ciphertext|ciphertext.*log').hasMatch(line),
            isFalse,
            reason: '$file must never log ciphertext',
          );
        }
      }
    });
  });
}

List<String> _dartFilesUnder(String dir) {
  final root = Directory(dir);
  if (!root.existsSync()) {
    return [];
  }
  final files = <String>[];
  for (final entity in root.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      files.add(entity.path);
    }
  }
  return files;
}

/// Strips `//` line comments and `///` doc comments so the scans above only
/// see executable code — security doc-comments themselves are expected.
Iterable<String> _codeLines(String source) sync* {
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
      continue;
    }
    // Cut inline trailing comments on the same line.
    final code = line.split('//').first;
    yield code;
  }
}
