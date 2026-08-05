import 'package:flutter/material.dart';

/// Single source of truth for all colors in Personal OS.
/// Change a value here, it updates everywhere the app uses AppColors.
class AppColors {
  AppColors._();

  // Brand / accent
  static const Color primary = Color(0xFF6C63FF);
  static const Color primaryDark = Color(0xFF4E46D1);
  static const Color accent = Color(0xFF00C2A8);

  // Backgrounds
  static const Color background = Color(0xFFF7F7FB);
  static const Color surface = Colors.white;
  static const Color surfaceDark = Color(0xFF1C1C24);
  static const Color backgroundDark = Color(0xFF121216);

  // Text
  static const Color textPrimary = Color(0xFF1A1A1E);
  static const Color textSecondary = Color(0xFF6B6B76);
  static const Color textOnPrimary = Colors.white;

  // Status / semantic
  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFFF3B30);
  static const Color skip = Color(0xFF8E8E93); // habit skip vs miss (later)

  // Priority (task tile left-border + form selector)
  static const Color priorityLow = Color(0xFF8E8E93);
  static const Color priorityMedium = Color(0xFFFFB020);
  static const Color priorityHigh = Color(0xFFFF3B30);

  // Streak / heatmap intensity scale (light -> dark, 5 steps) — for later
  static const List<Color> heatmapScale = [
    Color(0xFFEBEDF0),
    Color(0xFFC6E7D4),
    Color(0xFF8FD4A8),
    Color(0xFF4CBF7A),
    Color(0xFF1E9E52),
  ];

  static Color priorityColor(String priorityName) {
    switch (priorityName) {
      case 'high':
        return priorityHigh;
      case 'low':
        return priorityLow;
      default:
        return priorityMedium;
    }
  }
}

class AppTheme {
  AppTheme._();

  static ThemeData light = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: AppColors.background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.light,
      primary: AppColors.primary,
      surface: AppColors.surface,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surface,
      foregroundColor: AppColors.textPrimary,
      elevation: 0,
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: AppColors.textPrimary),
      bodyMedium: TextStyle(color: AppColors.textPrimary),
      bodySmall: TextStyle(color: AppColors.textSecondary),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );

  static ThemeData dark = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: AppColors.backgroundDark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: Brightness.dark,
      primary: AppColors.primary,
      surface: AppColors.surfaceDark,
      error: AppColors.error,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.surfaceDark,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    cardTheme: CardThemeData(
      color: AppColors.surfaceDark,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textOnPrimary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
  );
}