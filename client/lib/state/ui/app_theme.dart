import 'package:flutter/material.dart';

import 'vault_theme.dart';

/// Application theme configuration with dark mode support.
class AppTheme {
  AppTheme._();

  // ── Light theme ──
  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: VaultTheme.vaultBlue,
      scaffoldBackgroundColor: VaultTheme.vaultBg,
      appBarTheme: AppBarTheme(
        backgroundColor: VaultTheme.vaultBg,
        foregroundColor: VaultTheme.vaultText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: VaultTheme.vaultBlue.withValues(alpha: 0.12),
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.withValues(alpha: 0.2)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VaultTheme.vaultBlue, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.grey.withValues(alpha: 0.15),
        thickness: 0.5,
      ),
    );
  }

  // ── Dark theme ──
  static ThemeData dark() {
    const darkBg = Color(0xFF121212);
    const darkSurface = Color(0xFF1E1E1E);
    const darkCard = Color(0xFF252525);
    const darkText = Color(0xFFE0E0E0);
    const darkTextSecondary = Color(0xFF9E9E9E);

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: VaultTheme.vaultBlue,
      scaffoldBackgroundColor: darkBg,
      appBarTheme: AppBarTheme(
        backgroundColor: darkBg,
        foregroundColor: darkText,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      cardTheme: CardThemeData(
        color: darkCard,
        elevation: 1,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: darkSurface,
        indicatorColor: VaultTheme.vaultBlue.withValues(alpha: 0.2),
        elevation: 2,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.1)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: VaultTheme.vaultBlue, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(color: darkTextSecondary),
        hintStyle: TextStyle(color: darkTextSecondary.withValues(alpha: 0.6)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: VaultTheme.vaultBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: Colors.white.withValues(alpha: 0.08),
        thickness: 0.5,
      ),
      listTileTheme: ListTileThemeData(
        textColor: darkText,
        subtitleTextStyle: TextStyle(color: darkTextSecondary, fontSize: 12),
      ),
      iconTheme: const IconThemeData(color: darkText),
      textTheme: const TextTheme(
        bodyLarge: TextStyle(color: darkText),
        bodyMedium: TextStyle(color: darkText),
        bodySmall: TextStyle(color: darkTextSecondary),
        titleLarge: TextStyle(color: darkText),
        titleMedium: TextStyle(color: darkText),
        titleSmall: TextStyle(color: darkText),
        labelLarge: TextStyle(color: darkText),
      ),
    );
  }
}
