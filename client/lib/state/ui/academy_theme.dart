import 'package:flutter/material.dart';

/// Academy pillar design tokens (DESIGN.md §9 — textbook aesthetic).
///
/// The Academy uses a reading-friendly, print-register: cream paper
/// surfaces, ink text, a serif title stack and a single emerald accent
/// (optimized for low-data use and bright outdoor light per DESIGN.md
/// §9.1). These are FIXED, non-sensitive presentation constants — no user
/// data lives here.
class AcademyTheme {
  AcademyTheme._();

  /// Paper Cream #FAF6ED — screen backgrounds, textbook surfaces.
  static const Color paper = Color(0xFFFAF6ED);

  /// Ink #1F2430 — primary text (high contrast on cream for outdoor light).
  static const Color ink = Color(0xFF1F2430);

  /// Muted Ink #6E6A5E — secondary text, timestamps.
  static const Color muted = Color(0xFF6E6A5E);

  /// Emerald #2F6B4F — the Academy's single accent (progress, links).
  static const Color emerald = Color(0xFF2F6B4F);

  /// Surface #FFFFFF — card surfaces (light mode).
  static const Color surface = Color(0xFFFFFFFF);

  /// Textbook Rule #E3DCC8 — hairline dividers, chapter rules.
  static const Color rule = Color(0xFFE3DCC8);

  /// Serif stack for the masthead title / section headers (book register).
  static const String serifFont = 'serif';

  /// Mono stack for chapter stamps / module codes (cf. War Room stamps).
  static const String monoFont = 'monospace';
}
