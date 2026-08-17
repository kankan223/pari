import 'package:civic_commons/crypto/secure_key_storage.dart';
import 'package:civic_commons/identity/civic_pillar.dart';
import 'package:civic_commons/identity/identity_storage.dart';
import 'package:civic_commons/identity/local_unified_identity_service.dart';
import 'package:civic_commons/identity/pillar_claim.dart';
import 'package:civic_commons/identity/pillar_claim_sources.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Task 10.1 — Unified Identity Layer service tests.
///
/// SECURITY CHECKPOINT (10.1): the service composes MINIMUM claims per
/// pillar from the local sources — every pillar receives the shared blind
/// hash but only its allowed claims; no pillar ever receives the full
/// profile.
void main() {
  const validHash =
      '3f9c2b8d1a4e7f0a6c5b9d2e8f1a4c7b0d3e5f8a2b6c9d1e4f7a0b3c6e9d2f5a';

  late SecureKeyStorage secureStorage;
  late IdentityStorage identityStorage;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    secureStorage = SecureKeyStorage();
    await secureStorage.deleteAllKeys();
    identityStorage = IdentityStorage(secureStorage: secureStorage);
  });

  tearDown(() async {
    await secureStorage.deleteAllKeys();
  });

  MemoryPillarClaimSources sources() => MemoryPillarClaimSources(
        usernames: {validHash: 'savitri'},
        deviceKeys: {
          validHash: ['pub-key-1', 'pub-key-2']
        },
        pinCodes: {validHash: '800001'},
        karma: {validHash: '247'},
      );

  LocalUnifiedIdentityService service() => LocalUnifiedIdentityService(
        identityStorage: identityStorage,
        sources: sources(),
      );

  test('no identity → hasIdentity false, claims null', () async {
    final s = service();
    expect(await s.hasIdentity(), isFalse);
    expect(await s.blindHashId(), isNull);
    expect(await s.claimsFor(CivicPillar.vault), isNull);
  });

  test('stored identity → hasIdentity true + hash returned', () async {
    await identityStorage.storeBlindHashId(validHash);
    final s = service();
    expect(await s.hasIdentity(), isTrue);
    expect(await s.blindHashId(), validHash);
  });

  test('Vault claims: username + device keys, never pin/karma', () async {
    await identityStorage.storeBlindHashId(validHash);
    final claims = await service().claimsFor(CivicPillar.vault);
    expect(claims, isNotNull);
    expect(claims!.pillar, CivicPillar.vault);
    expect(claims.blindHashId, validHash);
    expect(claims.holds(PillarClaim.username), isTrue);
    expect(claims.holds(PillarClaim.deviceKeys), isTrue);
    expect(claims.holds(PillarClaim.pinCode), isFalse);
    expect(claims.holds(PillarClaim.karma), isFalse);
    expect(claims.username, 'savitri');
    expect(claims.deviceKeys, ['pub-key-1', 'pub-key-2']);
  });

  test('Ledger claims: pin code + karma, never username/device keys', () async {
    await identityStorage.storeBlindHashId(validHash);
    final claims = await service().claimsFor(CivicPillar.ledger);
    expect(claims, isNotNull);
    expect(claims!.pillar, CivicPillar.ledger);
    expect(claims.holds(PillarClaim.pinCode), isTrue);
    expect(claims.holds(PillarClaim.karma), isTrue);
    expect(claims.holds(PillarClaim.username), isFalse);
    expect(claims.holds(PillarClaim.deviceKeys), isFalse);
    expect(claims.pinCode, '800001');
    expect(claims.karma, '247');
  });

  test('War Room claims: NOTHING beyond the hash', () async {
    await identityStorage.storeBlindHashId(validHash);
    final claims = await service().claimsFor(CivicPillar.warRoom);
    expect(claims, isNotNull);
    expect(claims!.pillar, CivicPillar.warRoom);
    expect(claims.blindHashId, validHash);
    expect(claims.heldClaims, isEmpty);
    expect(claims.username, isNull);
    expect(claims.pinCode, isNull);
  });

  test('Academy claims: NOTHING beyond the hash', () async {
    await identityStorage.storeBlindHashId(validHash);
    final claims = await service().claimsFor(CivicPillar.academy);
    expect(claims, isNotNull);
    expect(claims!.pillar, CivicPillar.academy);
    expect(claims.blindHashId, validHash);
    expect(claims.heldClaims, isEmpty);
    expect(claims.username, isNull);
    expect(claims.karma, isNull);
  });

  test('a pillar with missing sources simply holds no claim', () async {
    await identityStorage.storeBlindHashId(validHash);
    final emptySources = MemoryPillarClaimSources();
    final s = LocalUnifiedIdentityService(
      identityStorage: identityStorage,
      sources: emptySources,
    );
    final vault = await s.claimsFor(CivicPillar.vault);
    expect(vault!.username, isNull);
    expect(vault.deviceKeys, isEmpty);
    final ledger = await s.claimsFor(CivicPillar.ledger);
    expect(ledger!.pinCode, isNull);
    expect(ledger.karma, isNull);
  });

  test('composeAllClaims builds the full per-pillar minimum map', () async {
    final all = await composeAllClaims(
      blindHashId: validHash,
      sources: sources(),
    );
    expect(all.keys.toSet(), CivicPillar.values.toSet());
    expect(all[CivicPillar.vault]!.username, 'savitri');
    expect(all[CivicPillar.ledger]!.pinCode, '800001');
    expect(all[CivicPillar.warRoom]!.heldClaims, isEmpty);
    expect(all[CivicPillar.academy]!.heldClaims, isEmpty);
  });
}
