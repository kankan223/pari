import 'civic_pillar.dart';
import 'identity_storage.dart';
import 'pillar_claim_sources.dart';
import 'pillar_claims.dart';
import 'unified_identity_service.dart';

/// [UnifiedIdentityService] backed by the local secure-storage blind hash +
/// the pillar claim sources (data layer, Task 10.1).
///
/// The blind hash lives in hardware-backed secure storage (the Phase 2.4
/// [IdentityStorage]); the per-pillar attributes are read from their OWN
/// pillar stores through [PillarClaimSources]. The service composes the
/// minimum claims per pillar — it never holds or builds a full profile.
class LocalUnifiedIdentityService implements UnifiedIdentityService {
  final IdentityStorage _identityStorage;
  final PillarClaimSources _sources;

  LocalUnifiedIdentityService({
    required IdentityStorage identityStorage,
    required PillarClaimSources sources,
  })  : _identityStorage = identityStorage,
        _sources = sources;

  @override
  Future<bool> hasIdentity() => _identityStorage.hasBlindHashId();

  @override
  Future<String?> blindHashId() => _identityStorage.getBlindHashId();

  @override
  Future<PillarClaims?> claimsFor(CivicPillar pillar) async {
    final blindHashId = await _identityStorage.getBlindHashId();
    if (blindHashId == null) {
      return null; // No identity established — onboarding must run first.
    }
    final all = await composeAllClaims(
      blindHashId: blindHashId,
      sources: _sources,
    );
    return all[pillar];
  }
}
