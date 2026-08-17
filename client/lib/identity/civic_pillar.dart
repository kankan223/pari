/// The four Civic Commons pillars (Task 10.1 — Unified Identity Layer).
///
/// Identity is composed AT THE EDGES: every pillar receives only the MINIMUM
/// claim it needs from the single shared blind hash (PRD §9.1) — no pillar
/// ever holds the full user profile.
///
/// SECURITY CHECKPOINT (Task 10.1): the pillar enum is an opaque value type —
/// it carries no identity fields, no payload, no claims. Claims are attached
/// by [PillarClaims] through the per-pillar allowlist, never by the pillar
/// itself.
enum CivicPillar {
  /// The Vault — private messaging. Claims: username, device keys.
  vault,

  /// The Daily Ledger — local news feed. Claims: pin code, karma.
  ledger,

  /// The War Room — OSINT / legal advocacy. Claims: none beyond the hash.
  warRoom,

  /// The Academy — open education. Claims: none beyond the hash.
  academy;

  /// Wire name for persistence + sync frames.
  String get wireName => switch (this) {
        CivicPillar.vault => 'vault',
        CivicPillar.ledger => 'ledger',
        CivicPillar.warRoom => 'war_room',
        CivicPillar.academy => 'academy',
      };

  /// Strict wire decode — unknown pillars throw (a corrupt/forged wire value
  /// can never masquerade as a real pillar).
  static CivicPillar fromWireName(String raw) => switch (raw) {
        'vault' => CivicPillar.vault,
        'ledger' => CivicPillar.ledger,
        'war_room' => CivicPillar.warRoom,
        'academy' => CivicPillar.academy,
        _ => throw ArgumentError('Unknown civic pillar: $raw'),
      };

  /// Human-readable pillar name (fixed labels only — never identity data).
  String get displayName => switch (this) {
        CivicPillar.vault => 'The Vault',
        CivicPillar.ledger => 'The Daily Ledger',
        CivicPillar.warRoom => 'The War Room',
        CivicPillar.academy => 'The Academy',
      };
}
