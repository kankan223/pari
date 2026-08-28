import 'package:flutter/material.dart';

/// Vault pillar design tokens (DESIGN.md §2.3, §6).
///
/// The Vault uses a classified-document register: Vault Blue, black
/// redaction bars, dense mono type for identifiers. These are FIXED,
/// non-sensitive presentation constants — no user data lives here.
class VaultTheme {
  VaultTheme._();

  /// Vault Blue #1A3D6B — trustworthy, classified-document navy (masthead
  /// background, sent-bubble background, primary interactive color).
  static const Color vaultBlue = Color(0xFF1A3D6B);

  /// Solid black — redaction-bar background + pseudo-redaction marks.
  static const Color redactionBlack = Color(0xFF000000);

  /// The mono font stack for dense identifier/redaction typography.
  static const String monoFont = 'monospace';

  // ── Extended design tokens ──

  /// Background color for vault screens.
  static const Color vaultBg = Color(0xFFF5F5F0);

  /// Card/surface background.
  static const Color vaultCard = Colors.white;

  /// Primary text color.
  static const Color vaultText = Color(0xFF1A1A1A);

  /// Secondary text color.
  static const Color vaultTextSecondary = Color(0xFF757575);

  /// Success color.
  static const Color vaultSuccess = Color(0xFF4CAF50);

  /// Warning color.
  static const Color vaultWarning = Color(0xFFFF9800);

  /// Error/danger color.
  static const Color vaultError = Color(0xFFF44336);
}
