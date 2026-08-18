import 'package:flutter/material.dart';

import '../../state/domain/karma_state.dart';

/// Presentation attributes for a karma tier badge (Task 10.3).
///
/// A pure value object mapping each [KarmaTier] band to its deterministic
/// visual tokens — color, icon glyph, display label, and short description.
/// No identity, no PII, no runtime state: the same balance always produces
/// the same badge on every device.
///
/// SECURITY CHECKPOINT (10.3): the badge consumes ONLY the public integer
/// balance (via [KarmaTier.forBalance]) and returns fixed, non-sensitive
/// presentation constants. No blind hash, no actor, no phone ever enters
/// the badge computation.
class KarmaBadge {
  const KarmaBadge._({
    required this.tier,
    required this.color,
    required this.icon,
    required this.label,
    required this.description,
  });

  /// The underlying tier band.
  final KarmaTier tier;

  /// The primary accent color for this tier.
  final Color color;

  /// The icon glyph for this tier.
  final IconData icon;

  /// The short display label (e.g. "Citizen", "Council").
  final String label;

  /// A one-line description for tooltips and accessibility.
  final String description;

  /// The badge for a given public karma [balance].
  ///
  /// Deterministic, pure, and monotone in balance — higher balance always
  /// yields the same or higher badge.
  factory KarmaBadge.forBalance(int balance) {
    final tier = KarmaTier.forBalance(balance);
    return _badges[tier]!;
  }

  /// The badge for an explicit [tier].
  factory KarmaBadge.forTier(KarmaTier tier) => _badges[tier]!;

  static final Map<KarmaTier, KarmaBadge> _badges = {
    KarmaTier.citizen: const KarmaBadge._(
      tier: KarmaTier.citizen,
      color: Color(0xFF6B6B7A), // muted gray — outline ring
      icon: Icons.circle_outlined,
      label: 'Citizen',
      description: 'New member — 0–49 karma',
    ),
    KarmaTier.contributor: const KarmaBadge._(
      tier: KarmaTier.contributor,
      color: Color(0xFFD4870F), // Civic Gold — half-fill
      icon: Icons.change_circle_outlined,
      label: 'Contributor',
      description: 'Active participant — 50–99 karma',
    ),
    KarmaTier.validator: const KarmaBadge._(
      tier: KarmaTier.validator,
      color: Color(0xFFD4870F), // Civic Gold — full ring
      icon: Icons.check_circle_outline,
      label: 'Validator',
      description: 'Trusted contributor — 100–149 karma',
    ),
    KarmaTier.analyst: const KarmaBadge._(
      tier: KarmaTier.analyst,
      color: Color(0xFF1A3D6B), // Vault Blue — star ring
      icon: Icons.stars_outlined,
      label: 'Analyst',
      description: 'Expert analyst — 150–499 karma',
    ),
    KarmaTier.council: const KarmaBadge._(
      tier: KarmaTier.council,
      color: Color(0xFF1C1C2E), // Ink — hexagon ring
      icon: Icons.hexagon_outlined,
      label: 'Council',
      description: 'Moderator Council — 500+ karma',
    ),
  };
}
