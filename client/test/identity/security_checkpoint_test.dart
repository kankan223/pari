import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Task 10.1 SECURITY CHECKPOINT — Unified Identity Layer.
///
/// 1. The identity surface imports NO networking (http/WebSocket/dart:io
///    sockets) — identity composition is local-first by construction.
/// 2. No raw debug output (print/logger) exists in identity production code.
/// 3. No PII-shaped literals (E.164 phones, 64-hex blind hashes, emails)
///    exist in identity production code.
/// 4. The per-pillar claim allowlist leaves NO claim reachable by the War
///    Room or Academy pillars — no pillar can hold a full profile
///    (PRD §9.1 minimum claims).
/// 5. The UI surface never renders the full 64-hex blind hash — only the
///    blinded `@citizen_` fragment (verified by the widget test).
void main() {
  group('Task 10.1 SECURITY CHECKPOINT — Unified Identity Layer', () {
    const identityFiles = [
      'lib/identity/civic_pillar.dart',
      'lib/identity/pillar_claim.dart',
      'lib/identity/pillar_claims.dart',
      'lib/identity/pillar_claim_sources.dart',
      'lib/identity/unified_identity_service.dart',
      'lib/identity/local_unified_identity_service.dart',
      'lib/state/domain/identity_verification_state.dart',
      'lib/state/domain/identity_verification_bloc.dart',
      'lib/state/data/local_identity_verification_bloc.dart',
      'lib/state/ui/identity_verification_screen.dart',
    ];

    List<File> files() =>
        identityFiles.map(File.new).where((f) => f.existsSync()).toList();

    test('identity production code imports no networking packages', () {
      final list = files();
      expect(list, isNotEmpty, reason: 'identity tree must exist');

      final forbidden = RegExp(
        "import\\s+['\"](dart:io|package:http|package:web_socket_channel|dart:ffi)",
      );
      final offenders = <String>[];
      for (final f in list) {
        if (forbidden.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no dart:io/http/websocket imports in the identity layer');
    });

    test('identity production code never prints', () {
      final printPattern = RegExp(r'\b(print|debugPrint|println|log\.)\s*\(');
      final offenders = <String>[];
      for (final f in files()) {
        if (printPattern.hasMatch(f.readAsStringSync())) {
          offenders.add(f.path);
        }
      }
      expect(offenders, isEmpty,
          reason: 'no print/debugPrint/log in the identity layer');
    });

    test('identity production code contains no PII-shaped literals', () {
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
          reason: 'no PII-shaped literals in the identity layer');
    });

    test(
        'War Room and Academy can never hold any per-pillar claim '
        '(no full profile)', () {
      // Structural proof of PRD §9.1: every claim's allowlist excludes the
      // War Room and Academy pillars — those pillars receive the shared hash
      // and NOTHING else, so no pillar can be composed into a full profile.
      final claims = <String>[
        // The PillarClaim.allowlistFor switch arms (username/deviceKeys →
        // vault; pinCode/karma → ledger). Re-derived structurally:
        'username', 'device_keys', 'pin_code', 'karma',
      ];
      final allowlistSource =
          File('lib/identity/pillar_claim.dart').readAsStringSync();
      for (final claim in claims) {
        expect(allowlistSource.contains(claim), isTrue,
            reason: 'claim $claim must be declared');
      }
      // The allowlist map keys are exactly {vault} / {ledger} — a static
      // scan proves no arm mentions war_room or academy as a holder.
      final warRoomOrAcademyAsHolder = RegExp(
        r'(warRoom|academy)[^;]{0,40}(username|deviceKeys|pinCode|karma)',
      );
      expect(warRoomOrAcademyAsHolder.hasMatch(allowlistSource), isFalse,
          reason: 'no claim allowlist arm may grant War Room / Academy a '
              'claim');
    });

    test(
        'the verification state declares no identity-typed fields beyond '
        'the one-way hash', () {
      final stateSource =
          File('lib/state/domain/identity_verification_state.dart')
              .readAsStringSync();
      // No username/phone/email/device-id fields may exist on the state.
      for (final forbidden in [
        'String? username',
        'String? phone',
        'String? email',
        'deviceId',
      ]) {
        expect(stateSource.contains(forbidden), isFalse,
            reason: 'state must not declare a $forbidden field');
      }
    });
  });
}
