import 'package:civic_commons/identity/civic_pillar.dart';
import 'package:civic_commons/identity/pillar_claim.dart';
import 'package:civic_commons/identity/pillar_claims.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 10.1 — Unified Identity Layer domain tests.
///
/// SECURITY CHECKPOINT (10.1): the per-pillar claim allowlist is enforced AT
/// PROJECTION TIME — no pillar can ever receive a claim outside its minimum
/// set, so no pillar can be composed into a full profile.
void main() {
  const validHash =
      '3f9c2b8d1a4e7f0a6c5b9d2e8f1a4c7b0d3e5f8a2b6c9d1e4f7a0b3c6e9d2f5a';

  group('CivicPillar', () {
    test('wire names round-trip for all four pillars', () {
      for (final pillar in CivicPillar.values) {
        expect(CivicPillar.fromWireName(pillar.wireName), pillar);
      }
    });

    test('unknown wire names throw', () {
      expect(() => CivicPillar.fromWireName('telepathy'), throwsArgumentError);
    });

    test('display names are fixed labels', () {
      expect(CivicPillar.vault.displayName, 'The Vault');
      expect(CivicPillar.ledger.displayName, 'The Daily Ledger');
      expect(CivicPillar.warRoom.displayName, 'The War Room');
      expect(CivicPillar.academy.displayName, 'The Academy');
    });
  });

  group('PillarClaim allowlist (PRD §9.1 minimum claims)', () {
    test('Vault holds username + deviceKeys only', () {
      expect(
        PillarClaim.allowlistFor(PillarClaim.username),
        {CivicPillar.vault},
      );
      expect(
        PillarClaim.allowlistFor(PillarClaim.deviceKeys),
        {CivicPillar.vault},
      );
    });

    test('Ledger holds pinCode + karma only', () {
      expect(
        PillarClaim.allowlistFor(PillarClaim.pinCode),
        {CivicPillar.ledger},
      );
      expect(
        PillarClaim.allowlistFor(PillarClaim.karma),
        {CivicPillar.ledger},
      );
    });

    test('War Room and Academy hold NO extra claims', () {
      for (final claim in PillarClaim.values) {
        expect(
          PillarClaim.allowlistFor(claim).contains(CivicPillar.warRoom),
          isFalse,
          reason: 'War Room must not hold $claim',
        );
        expect(
          PillarClaim.allowlistFor(claim).contains(CivicPillar.academy),
          isFalse,
          reason: 'Academy must not hold $claim',
        );
      }
    });

    test('wire names round-trip', () {
      for (final claim in PillarClaim.values) {
        expect(PillarClaim.fromWireName(claim.wireName), claim);
      }
    });

    test('unknown claim wire names throw', () {
      expect(
          () => PillarClaim.fromWireName('social_credit'), throwsArgumentError);
    });
  });

  group('PillarClaims projection (allowlist-enforced)', () {
    test('Vault projection carries username + device keys', () {
      final claims = PillarClaims.compose(
        pillar: CivicPillar.vault,
        blindHashId: validHash,
        username: 'savitri',
        deviceKeys: ['pub-key-1'],
      );
      expect(claims.holds(PillarClaim.username), isTrue);
      expect(claims.holds(PillarClaim.deviceKeys), isTrue);
      expect(claims.holds(PillarClaim.pinCode), isFalse);
      expect(claims.holds(PillarClaim.karma), isFalse);
    });

    test('Vault CANNOT hold pinCode or karma (throws)', () {
      expect(
        () => PillarClaims.compose(
          pillar: CivicPillar.vault,
          blindHashId: validHash,
          pinCode: '800001',
        ),
        throwsArgumentError,
      );
      expect(
        () => PillarClaims.compose(
          pillar: CivicPillar.vault,
          blindHashId: validHash,
          karma: '247',
        ),
        throwsArgumentError,
      );
    });

    test('Ledger projection carries pinCode + karma', () {
      final claims = PillarClaims.compose(
        pillar: CivicPillar.ledger,
        blindHashId: validHash,
        pinCode: '800001',
        karma: '247',
      );
      expect(claims.holds(PillarClaim.pinCode), isTrue);
      expect(claims.holds(PillarClaim.karma), isTrue);
      expect(claims.holds(PillarClaim.username), isFalse);
      expect(claims.holds(PillarClaim.deviceKeys), isFalse);
    });

    test('Ledger CANNOT hold username or deviceKeys (throws)', () {
      expect(
        () => PillarClaims.compose(
          pillar: CivicPillar.ledger,
          blindHashId: validHash,
          username: 'savitri',
        ),
        throwsArgumentError,
      );
      expect(
        () => PillarClaims.compose(
          pillar: CivicPillar.ledger,
          blindHashId: validHash,
          deviceKeys: ['pub-key-1'],
        ),
        throwsArgumentError,
      );
    });

    test('War Room and Academy projections hold NOTHING beyond the hash', () {
      for (final pillar in [CivicPillar.warRoom, CivicPillar.academy]) {
        final claims = PillarClaims.compose(
          pillar: pillar,
          blindHashId: validHash,
        );
        expect(claims.heldClaims, isEmpty);
        expect(claims.blindHashId, validHash);
      }
    });

    test('War Room / Academy reject ANY extra claim (throws)', () {
      for (final pillar in [CivicPillar.warRoom, CivicPillar.academy]) {
        for (final claim in PillarClaim.values) {
          final args = <String, Object?>{
            'pillar': pillar,
            'blindHashId': validHash,
          };
          switch (claim) {
            case PillarClaim.username:
              args['username'] = 'x';
            case PillarClaim.deviceKeys:
              args['deviceKeys'] = ['k'];
            case PillarClaim.pinCode:
              args['pinCode'] = '800001';
            case PillarClaim.karma:
              args['karma'] = '1';
          }
          expect(
            () => PillarClaims.compose(
              pillar: pillar,
              blindHashId: validHash,
              username: args['username'] as String?,
              deviceKeys: (args['deviceKeys'] as List<String>?) ?? const [],
              pinCode: args['pinCode'] as String?,
              karma: args['karma'] as String?,
            ),
            throwsArgumentError,
            reason: '$pillar must reject the $claim claim',
          );
        }
      }
    });

    test('blind hash is normalized to lowercase 64-hex', () {
      final claims = PillarClaims.compose(
        pillar: CivicPillar.vault,
        blindHashId: validHash.toUpperCase(),
      );
      expect(claims.blindHashId, validHash);
    });

    test('malformed blind hash throws', () {
      expect(
        () => PillarClaims.compose(
          pillar: CivicPillar.vault,
          blindHashId: 'not-a-hash',
        ),
        throwsArgumentError,
      );
    });

    test('displayHandle is a blinded fragment — never the full hash', () {
      final claims = PillarClaims.compose(
        pillar: CivicPillar.vault,
        blindHashId: validHash,
      );
      expect(claims.displayHandle, '@citizen_3f9c2b');
      expect(claims.displayHandle.contains(validHash), isFalse);
      // The full 64-hex hash never appears in the display form.
      expect(validHash.length, 64);
      expect(claims.displayHandle.length, lessThan(64));
    });

    test('equality compares the full projection', () {
      final a = PillarClaims.compose(
        pillar: CivicPillar.ledger,
        blindHashId: validHash,
        pinCode: '800001',
        karma: '247',
      );
      final b = PillarClaims.compose(
        pillar: CivicPillar.ledger,
        blindHashId: validHash,
        pinCode: '800001',
        karma: '247',
      );
      final c = PillarClaims.compose(
        pillar: CivicPillar.vault,
        blindHashId: validHash,
      );
      expect(a, equals(b));
      expect(a == c, isFalse);
    });
  });
}
