import 'package:flutter/material.dart';

import '../../ledger/domain/ledger_category.dart';

/// Ledger pillar design tokens (DESIGN.md §2.4, §4.4).
///
/// The Ledger uses a broadsheet newspaper register: Ledger Green masthead,
/// paper-colored surfaces, ink text, a heavy rule line. These are FIXED,
/// non-sensitive presentation constants — no user data lives here.
class LedgerTheme {
  LedgerTheme._();

  /// Ledger Green #1E4D38 — broadsheet forest green (masthead background,
  /// primary interactive color, #CivicInfrastructure chip color).
  static const Color ledgerGreen = Color(0xFF1E4D38);

  /// Ink #1C1C2E — primary text / app shell background.
  static const Color ink = Color(0xFF1C1C2E);

  /// Paper #F5F1E8 — screen backgrounds, card surfaces.
  static const Color paper = Color(0xFFF5F1E8);

  /// Civic Gold #D4870F — primary CTA, karma indicators, #SatireAndCulture.
  static const Color civicGold = Color(0xFFD4870F);

  /// Alert Red #B52A2A — danger/errors, #BreakingLocal (sparingly).
  static const Color alertRed = Color(0xFFB52A2A);

  /// Verified Emerald #1E6B3A — success, verified badges.
  static const Color verifiedEmerald = Color(0xFF1E6B3A);

  /// Muted #6B6B7A — secondary text, timestamps.
  static const Color muted = Color(0xFF6B6B7A);

  /// Surface #FFFFFF — card backgrounds (light mode).
  static const Color surface = Color(0xFFFFFFFF);

  /// Divider #E0DDD6 — horizontal rules, card borders.
  static const Color divider = Color(0xFFE0DDD6);

  /// Academy Teal #1A5C68 — #StudentRights chip color.
  static const Color academyTeal = Color(0xFF1A5C68);

  /// War Room Amber #8B3A0F — #ConsumerWatch chip color.
  static const Color warRoomAmber = Color(0xFF8B3A0F);

  /// The mono/serif stack for the newspaper nameplate.
  static const String mastheadFont = 'serif';

  /// Maps a [LedgerCategory] to its chip accent color (DESIGN.md §4.4).
  static Color categoryColor(LedgerCategory category) => switch (category) {
        LedgerCategory.civicInfrastructure => ledgerGreen,
        LedgerCategory.studentRights => academyTeal,
        LedgerCategory.consumerWatch => warRoomAmber,
        LedgerCategory.satireAndCulture => civicGold,
        LedgerCategory.breakingLocal => alertRed,
      };
}
