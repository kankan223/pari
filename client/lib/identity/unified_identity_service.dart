import 'civic_pillar.dart';
import 'pillar_claims.dart';

/// Port for the Unified Identity Layer (Task 10.1).
///
/// One blind hash per person, shared READ-ONLY across all four pillars.
/// Every pillar requests ONLY the minimum claim it needs (PRD §9.1):
///
///   Vault      → username, deviceKeys
///   Ledger     → pinCode, karma
///   War Room   → nothing beyond the hash
///   Academy    → nothing beyond the hash
///
/// SECURITY CHECKPOINT (Task 10.1): [claimsFor] returns ONLY the claims the
/// pillar is permitted to hold (allowlist-enforced at projection time) — no
/// pillar can ever receive the full user profile. The service holds no
/// profile of its own: it composes claims at the edges from the local claim
/// sources (the blind hash in secure storage + public pillar attributes).
abstract class UnifiedIdentityService {
  /// Whether the device has a shared identity (blind hash) established.
  Future<bool> hasIdentity();

  /// The shared blind hash, or null when not established.
  Future<String?> blindHashId();

  /// The MINIMUM claims projection for [pillar].
  ///
  /// Returns null when the device has no identity established yet (the
  /// onboarding verification flow must run first). When established, returns
  /// a [PillarClaims] carrying the shared hash + ONLY the pillar's allowed
  /// claims (username/deviceKeys for Vault; pinCode/karma for Ledger;
  /// nothing extra for War Room / Academy).
  Future<PillarClaims?> claimsFor(CivicPillar pillar);
}
