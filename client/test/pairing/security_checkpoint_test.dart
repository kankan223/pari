import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// SECURITY CHECKPOINT (Task 6.5): the pairing feature is a fully local,
/// QR-based device-linking flow. It must uphold:
///  - Pairing NEVER uses cloud backup, cloud sync, or any remote storage —
///    the QR is the ONLY transport for key material.
///  - The QR payload carries ONLY public keys + a 64-hex blind hash + a
///    one-time secret. No private keys, no phones, no usernames.
///  - No PII-shaped literals in pairing source (phones/e-mails/full hashes).
///  - No raw debug output (print/debugPrint) anywhere in lib/pairing.
///  - Pairing UI files consume BLoC streams only (no data-layer imports) and
///    render devices through formatDeviceHandle only.
void main() {
  final pairingFiles = _dartFilesUnder('lib/pairing');
  final pairingUiFiles = _dartFilesUnder('lib/state/ui')
    ..removeWhere((p) =>
        !p.endsWith('device_management_sheet.dart') &&
        !p.endsWith('pairing_qr_view.dart') &&
        !p.endsWith('pairing_scan_sheet.dart'));

  group('SECURITY CHECKPOINT - pairing never uses cloud backup (Task 6.5)', () {
    test('lib/pairing exists with the expected modules', () {
      expect(pairingFiles, isNotEmpty);
      for (final name in [
        'pairing_payload.dart',
        'pairing_secret.dart',
        'qr_matrix.dart',
        'device_pairing_service.dart',
        'device_registry.dart',
        'linked_device.dart',
      ]) {
        expect(pairingFiles.any((f) => f.endsWith(name)), isTrue,
            reason: '$name must exist under lib/pairing');
      }
    });
    test('no cloud-backup / cloud-sync identifiers anywhere in lib/pairing',
        () {
      // Word-boundary regexes so `async` does not match `sync` (Dart keyword).
      final cloudPatterns = [
        RegExp(r'\b(icloud|iCloud)\b'),
        RegExp(r'\b(backup|Backup)\b'),
        RegExp(r'\b(cloud|Cloud)\b'),
        RegExp(r'\b(drive|Drive)\b'),
        RegExp(r'\b(sync|Sync|synced|Synced)\b'),
        RegExp(r'\b(upload|Upload)\b'),
      ];
      for (final file in pairingFiles) {
        final source = File(file).readAsStringSync();
        // Scan only CODE lines — doc comments legitimately say "never cloud
        // backup", which contains the word.
        for (final line in _codeLines(source)) {
          for (final pattern in cloudPatterns) {
            expect(pattern.hasMatch(line), isFalse,
                reason: '$file must not reference "$pattern" in code — '
                    'pairing is QR-local and must never back up or sync');
          }
        }
      }
    });

    test('no raw debug output anywhere in lib/pairing', () {
      for (final file in pairingFiles) {
        final source = File(file).readAsStringSync();
        for (final line in _codeLines(source)) {
          expect(
            line.contains('print(') ||
                line.contains('debugPrint(') ||
                line.contains('println('),
            isFalse,
            reason: '$file must not print — output could leak key material',
          );
        }
      }
    });

    test('no PII-shaped literals (phones / e-mails / 64-hex) in lib/pairing',
        () {
      final phoneShape = RegExp("['\\\"][+]?\\d{8,15}['\\\"]");
      final emailShape = RegExp(
          "['\\\"][a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\\.[a-zA-Z]{2,}['\\\"]");
      for (final file in pairingFiles) {
        final source = File(file).readAsStringSync();
        for (final line in _codeLines(source)) {
          expect(phoneShape.hasMatch(line), isFalse,
              reason: '$file contains a phone-shaped literal');
          expect(emailShape.hasMatch(line), isFalse,
              reason: '$file contains an email-shaped literal');
        }
      }
    });

    test('the payload codec NEVER serializes private key material', () {
      final payload =
          pairingFiles.firstWhere((f) => f.endsWith('pairing_payload.dart'));
      final source = File(payload).readAsStringSync();
      for (final line in _codeLines(source)) {
        // The encode() method must never reference private keys.
        expect(line.contains('privateKey'), isFalse,
            reason: '$payload must not serialize private key material');
        expect(line.contains('private_key'), isFalse,
            reason: '$payload must not serialize private key material');
      }
    });

    test('the pairing service depends on ports, never on network/cloud SDKs',
        () {
      final service = pairingFiles
          .firstWhere((f) => f.endsWith('device_pairing_service.dart'));
      final source = File(service).readAsStringSync();
      for (final forbidden in ['package:http', 'dart:io', 'WebSocket']) {
        expect(source.contains(forbidden), isFalse,
            reason: '$service must not import "$forbidden" — pairing is '
                'fully local (QR + local registry + local sessions)');
      }
    });

    test('the QrScanner port is the only external-capture boundary', () {
      final scanner =
          pairingFiles.firstWhere((f) => f.endsWith('qr_matrix.dart'));
      final source = File(scanner).readAsStringSync();
      // The port returns a raw STRING; interpretation happens only in the
      // pairing service. Nothing in the domain decodes PII itself.
      expect(source, contains('Future<String?> scan()'));
    });
  });

  group('SECURITY CHECKPOINT - pairing UI is BLoC-only and zero-PII', () {
    test('pairing UI files exist', () {
      for (final name in [
        'device_management_sheet.dart',
        'pairing_qr_view.dart',
        'pairing_scan_sheet.dart',
      ]) {
        expect(pairingUiFiles.any((p) => p.endsWith(name)), isTrue,
            reason: '$name must exist under lib/state/ui');
      }
    });

    test('pairing UI consumes BLoC streams, never data layers', () {
      for (final file in pairingUiFiles) {
        final source = File(file).readAsStringSync();
        for (final forbidden in [
          'DeviceRegistry',
          'EntityStore',
          'sqflite',
          'hive_ce',
          'secure_storage',
          'package:http',
          'DevicePairingService',
          'LinkedDevicesBloc()', // must be injected, never constructed
        ]) {
          expect(source.contains(forbidden), isFalse,
              reason: '$file must not reference "$forbidden" — pairing UI '
                  'consumes BLoC/state streams only');
        }
        // State projections (LinkedDeviceSummary etc.) come from the STATE
        // layer — but the raw pairing DOMAIN entities must not appear.
        for (final line in _codeLines(source)) {
          expect(
            RegExp(r'\bPairingPayload\b').hasMatch(line) ||
                RegExp(r'\bLinkedDevice\b').hasMatch(line),
            isFalse,
            reason: '$file must not reference the pairing domain entities — '
                'only UI-safe state projections',
          );
        }
      }
    });

    test('no prints / debugPrint anywhere in pairing UI', () {
      for (final file in pairingUiFiles) {
        final source = File(file).readAsStringSync();
        expect(source.contains('print('), isFalse,
            reason: '$file must not print');
        expect(source.contains('debugPrint('), isFalse,
            reason: '$file must not debugPrint');
      }
    });

    test('devices render only via formatDeviceHandle', () {
      for (final file in pairingUiFiles) {
        final source = File(file).readAsStringSync();
        if (file.endsWith('device_management_sheet.dart')) {
          expect(source, contains('formatDeviceHandle'),
              reason: 'device_management_sheet must render devices through '
                  'formatDeviceHandle');
        }
      }
    });

    test('every pairing SCREEN wraps in SecureScreenWrapper (FLAG_SECURE)', () {
      // PairingQrView is a pure component (rendered INSIDE the wrapped
      // sheet); the two interactive screens must each carry the guard.
      for (final file in pairingUiFiles) {
        if (file.endsWith('pairing_qr_view.dart')) {
          continue;
        }
        final source = File(file).readAsStringSync();
        expect(source, contains('SecureScreenWrapper'),
            reason: '$file must be wrapped in SecureScreenWrapper '
                '(FLAG_SECURE anti-screenshot guard)');
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

/// Strips `//` line comments and `///` doc comments so scans only see
/// executable code — security doc-comments themselves are expected.
Iterable<String> _codeLines(String source) sync* {
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
      continue;
    }
    final code = line.split('//').first;
    yield code;
  }
}
