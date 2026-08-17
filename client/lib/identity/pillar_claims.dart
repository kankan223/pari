import 'civic_pillar.dart';
import 'pillar_claim.dart';

/// A per-pillar, minimum-claims projection of the shared identity
/// (Task 10.1 — Unified Identity Layer, PRD §9.1).
///
/// Every pillar receives the SAME read-only blind hash (the shared identity)
/// plus ONLY the claims its allowlist permits:
///
///   Vault      → username, deviceKeys
///   Ledger     → pinCode, karma
///   War Room   → nothing beyond the hash
///   Academy    → nothing beyond the hash
///
/// SECURITY CHECKPOINT (Task 10.1): construction ENFORCES the allowlist — a
/// claim the pillar is not permitted to hold throws [ArgumentError], so a
/// caller can never accidentally (or maliciously) compose a full profile for
/// a pillar. A pillar either holds a claim or does not; the projection is
/// immutable and carries zero raw PII (the blind hash is one-way, usernames
/// are public handles, pin codes are coarse civic scopes, karma is a public
/// score).
class PillarClaims {
  final CivicPillar pillar;

  /// The shared read-only blind hash (available to EVERY pillar).
  final String blindHashId;

  /// Public username (Vault only).
  final String? username;

  /// Device public keys (Vault only).
  final List<String> deviceKeys;

  /// Coarse civic pin-code scope (Ledger only).
  final String? pinCode;

  /// Public karma score (Ledger only).
  final String? karma;

  const PillarClaims._({
    required this.pillar,
    required this.blindHashId,
    this.username,
    this.deviceKeys = const [],
    this.pinCode,
    this.karma,
  });

  /// Composes the projection, ENFORCING the per-pillar claim allowlist.
  ///
  /// Throws [ArgumentError] when a claim is provided for a pillar that is not
  /// permitted to hold it (SECURITY CHECKPOINT 10.1).
  static PillarClaims compose({
    required CivicPillar pillar,
    required String blindHashId,
    String? username,
    List<String> deviceKeys = const [],
    String? pinCode,
    String? karma,
  }) {
    if (username != null &&
        !PillarClaim.allowlistFor(PillarClaim.username).contains(pillar)) {
      throw ArgumentError('Pillar $pillar cannot hold the username claim');
    }
    if (deviceKeys.isNotEmpty &&
        !PillarClaim.allowlistFor(PillarClaim.deviceKeys).contains(pillar)) {
      throw ArgumentError('Pillar $pillar cannot hold the deviceKeys claim');
    }
    if (pinCode != null &&
        !PillarClaim.allowlistFor(PillarClaim.pinCode).contains(pillar)) {
      throw ArgumentError('Pillar $pillar cannot hold the pinCode claim');
    }
    if (karma != null &&
        !PillarClaim.allowlistFor(PillarClaim.karma).contains(pillar)) {
      throw ArgumentError('Pillar $pillar cannot hold the karma claim');
    }
    if (blindHashId.trim().length != 64) {
      throw ArgumentError('blindHashId must be a 64-hex blind hash');
    }
    return PillarClaims._(
      pillar: pillar,
      blindHashId: blindHashId.trim().toLowerCase(),
      username: username,
      deviceKeys: List.unmodifiable(deviceKeys),
      pinCode: pinCode,
      karma: karma,
    );
  }

  /// The claims this projection actually holds (for UI + tests).
  Set<PillarClaim> get heldClaims => {
        if (username != null) PillarClaim.username,
        if (deviceKeys.isNotEmpty) PillarClaim.deviceKeys,
        if (pinCode != null) PillarClaim.pinCode,
        if (karma != null) PillarClaim.karma,
      };

  /// Whether the projection holds [claim].
  bool holds(PillarClaim claim) => heldClaims.contains(claim);

  /// Non-PII display handle: `@citizen_` + the first 6 hex chars of the
  /// blind hash — the same blinded-handle rule as the Vault's peer handles
  /// (a full 64-hex hash is never rendered anywhere).
  String get displayHandle {
    final trimmed = blindHashId.trim().toLowerCase();
    final fragment = trimmed.length >= 6 ? trimmed.substring(0, 6) : trimmed;
    return '@citizen_$fragment';
  }

  @override
  bool operator ==(Object other) =>
      other is PillarClaims &&
      other.pillar == pillar &&
      other.blindHashId == blindHashId &&
      other.username == username &&
      _listEquals(other.deviceKeys, deviceKeys) &&
      other.pinCode == pinCode &&
      other.karma == karma;

  @override
  int get hashCode => Object.hash(pillar, blindHashId, username,
      Object.hashAll(deviceKeys), pinCode, karma);

  static bool _listEquals(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
