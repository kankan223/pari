import 'package:flutter/material.dart';

import '../../war_room/domain/case_severity.dart';

/// War Room pillar design tokens (DESIGN.md §2.1/§2.2/§8).
///
/// The War Room uses an intelligence-dossier register: charcoal dossier
/// ink, manila paper surfaces, amber severity classification bands, mono
/// case-stamp typography (JetBrains Mono per DESIGN.md §8.2). These are
/// FIXED, non-sensitive presentation constants — no user data lives here.
class WarRoomTheme {
  WarRoomTheme._();

  /// Dossier Ink #24221E — near-black charcoal (masthead background, stamp
  /// rule, primary text).
  static const Color dossierInk = Color(0xFF24221E);

  /// Manila Paper #F4EFE6 — screen backgrounds, dossier surfaces.
  static const Color manilaPaper = Color(0xFFF4EFE6);

  /// Surface #FFFFFF — card backgrounds (light mode).
  static const Color surface = Color(0xFFFFFFFF);

  /// Muted #6B6B7A — secondary text, timestamps.
  static const Color muted = Color(0xFF6B6B7A);

  /// Divider #E0DDD6 — dossier rules, card borders.
  static const Color divider = Color(0xFFE0DDD6);

  /// War Room Amber #B45309 — HIGH severity band, primary interactive
  /// accents, the "[+ File a new case]" action.
  static const Color amber = Color(0xFFB45309);

  /// The mono font stack for case stamps / classification bands.
  static const String monoFont = 'monospace';

  /// Severity band colors (DESIGN.md §8.2: HIGH amber, severity bands per
  /// level). Deterministic mapping — severity is a public case attribute.
  static Color severityColor(CaseSeverity severity) => switch (severity) {
        CaseSeverity.critical => const Color(0xFFB52A2A),
        CaseSeverity.high => amber,
        CaseSeverity.medium => const Color(0xFFD4870F),
        CaseSeverity.low => const Color(0xFF5B6B2E),
      };
}
