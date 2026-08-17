import 'civic_pillar.dart';

/// The minimum claims a pillar may request from the shared identity
/// (Task 10.1 — Unified Identity Layer, PRD §9.1).
///
/// Identity is composed at the edges: each pillar requests ONLY the claim it
/// needs and is denied everything else. The per-pillar allowlist below is the
/// single source of truth for the permission boundary:
///
///   Vault      → username, deviceKeys
///   Ledger     → pinCode, karma
///   War Room   → (none beyond the hash itself)
///   Academy    → (none beyond the hash itself)
///
/// SECURITY CHECKPOINT (Task 10.1): no pillar can request a claim outside its
/// allowlist — [PillarClaims.allowlistFor] throws on any violation, so the
/// service layer can never leak a full profile to a pillar. The blind hash
/// itself is the shared read-only identity (available to every pillar); the
/// claims below are the ONLY per-pillar attributes that may be composed.
enum PillarClaim {
  /// Public username (Vault messaging).
  username,

  /// Device public keys (Vault multi-device).
  deviceKeys,

  /// Coarse civic pin-code scope (Ledger feed scoping).
  pinCode,

  /// Public karma score (Ledger reputation).
  karma;

  /// The pillar(s) that may hold this claim (read-only minimum claims).
  static Set<CivicPillar> allowlistFor(PillarClaim claim) => switch (claim) {
        PillarClaim.username || PillarClaim.deviceKeys => {CivicPillar.vault},
        PillarClaim.pinCode || PillarClaim.karma => {CivicPillar.ledger},
      };

  /// Wire name for persistence + sync frames.
  String get wireName => switch (this) {
        PillarClaim.username => 'username',
        PillarClaim.deviceKeys => 'device_keys',
        PillarClaim.pinCode => 'pin_code',
        PillarClaim.karma => 'karma',
      };

  /// Strict wire decode — unknown claims throw.
  static PillarClaim fromWireName(String raw) => switch (raw) {
        'username' => PillarClaim.username,
        'device_keys' => PillarClaim.deviceKeys,
        'pin_code' => PillarClaim.pinCode,
        'karma' => PillarClaim.karma,
        _ => throw ArgumentError('Unknown pillar claim: $raw'),
      };
}
