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
}
