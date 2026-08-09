import 'package:flutter/material.dart';

/// Semantic colors — same across every theme palette.
class AppColors {
  AppColors._();

  static const Color success = Color(0xFF34C759);
  static const Color warning = Color(0xFFFFB020);
  static const Color error = Color(0xFFFF3B30);
  static const Color skip = Color(0xFF8E8E93);

  static const Color priorityLow = Color(0xFF8E8E93);
  static const Color priorityMedium = Color(0xFFFFB020);
  static const Color priorityHigh = Color(0xFFFF3B30);

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

/// Per-theme brand/background/text colors. Add a new palette here to reskin the app.
class ThemePalette {
  final String key;
  final String label;
  final Color primary;
  final Color accent;
  final Color background;
  final Color surface;
  final Color surfaceDark;
  final Color backgroundDark;
  final Color textPrimary;
  final Color textSecondary;
  final Color textOnPrimary;
  final List<Color> preview; // shown as swatch strip in Settings

  const ThemePalette({
    required this.key,
    required this.label,
    required this.primary,
    required this.accent,
    required this.background,
    required this.surface,
    required this.surfaceDark,
    required this.backgroundDark,
    required this.textPrimary,
    required this.textSecondary,
    required this.textOnPrimary,
    required this.preview,
  });
}

class AppThemePresets {
  AppThemePresets._();

  static const aurora = ThemePalette(
    key: 'aurora',
    label: 'Aurora',
    primary: Color(0xFF3A516A), // Plaudit
    accent: Color(0xFF0DBE9D), // Aare River
    background: Color(0xFFEAF2F1), // soft teal-gray tint — was a saturated #28BEBE that clashed with the muted navy/teal palette
    surface: Colors.white,
    surfaceDark: Color(0xFF18455D), // Ethereal Dance
    backgroundDark: Color(0xFF0C141C), // Midnight Edition
    textPrimary: Color(0xFF162F46), // NATO Blue
    textSecondary: Color(0xFF617180), // Hidden Harbour
    textOnPrimary: Colors.white,
    preview: [Color(0xFF18455D), Color(0xFF3A516A), Color(0xFF0DBE9D), Color(0xFF0C141C)],
  );

  static const midnightViolet = ThemePalette(
    key: 'midnightViolet',
    label: 'Midnight Violet',
    primary: Color(0xFF773344), // Wine Plum
    accent: Color(0xFFD44D5C), // Lobster Pink
    background: Color(0xFFF5E9E2), // Linen
    surface: Colors.white,
    surfaceDark: Color(0xFF2A1030),
    backgroundDark: Color(0xFF160029), // Midnight Violet
    textPrimary: Color(0xFF2A1030),
    textSecondary: Color(0xFF9B7A88),
    textOnPrimary: Colors.white,
    preview: [Color(0xFF160029), Color(0xFF773344), Color(0xFFD44D5C), Color(0xFFE3B5A4)],
  );

  static const purpleEmpire = ThemePalette(
    key: 'purpleEmpire',
    label: 'Purple Empire',
    primary: Color(0xFF5C4B57), // Purple Empire
    accent: Color(0xFFC8B4C4), // Pink Bravado
    background: Color(0xFFEBDFE7), // Ostrich Tail
    surface: Colors.white,
    surfaceDark: Color(0xFF352C39),
    backgroundDark: Color(0xFF261F28), // To Hell and Black
    textPrimary: Color(0xFF261F28),
    textSecondary: Color(0xFF978090), // Plum Swirl
    textOnPrimary: Colors.white,
    preview: [Color(0xFF261F28), Color(0xFF5C4B57), Color(0xFF978090), Color(0xFFC8B4C4)],
  );

  static const warmAmber = ThemePalette(
    key: 'warmAmber',
    label: 'Warm Amber',
    primary: Color(0xFFF78358), // Bonfire
    accent: Color(0xFFFECC64), // Quing Yellow
    background: Color(0xFFFFF6E8), // Apricot Ice
    surface: Colors.white,
    surfaceDark: Color(0xFF482420), // Tobi Brown
    backgroundDark: Color(0xFF2A1512),
    textPrimary: Color(0xFF482420),
    textSecondary: Color(0xFF8A5A4A),
    textOnPrimary: Colors.white,
    preview: [Color(0xFF482420), Color(0xFFB24D37), Color(0xFFF78358), Color(0xFFFECC64)],
  );

  static const all = [aurora, midnightViolet, purpleEmpire, warmAmber];

  static ThemePalette byKey(String key) =>
      all.firstWhere((p) => p.key == key, orElse: () => aurora);
}

class AppTheme {
  AppTheme._();

  static ThemeData light(ThemePalette p) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.light,
        scaffoldBackgroundColor: p.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: Brightness.light,
          primary: p.primary,
          surface: p.surface,
          error: AppColors.error,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: p.surface,
          foregroundColor: p.textPrimary,
          elevation: 0,
        ),
        textTheme: TextTheme(
          bodyLarge: TextStyle(color: p.textPrimary),
          bodyMedium: TextStyle(color: p.textPrimary),
          bodySmall: TextStyle(color: p.textSecondary),
        ),
        cardTheme: CardThemeData(
          color: p.surface,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.textOnPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.textOnPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: p.surface,
          indicatorColor: p.primary.withValues(alpha: 0.15),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? p.primary : p.textSecondary,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? p.primary : p.textSecondary,
            );
          }),
        ),
      );

  static ThemeData dark(ThemePalette p) => ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: p.backgroundDark,
        colorScheme: ColorScheme.fromSeed(
          seedColor: p.primary,
          brightness: Brightness.dark,
          primary: p.primary,
          surface: p.surfaceDark,
          error: AppColors.error,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: p.surfaceDark,
          foregroundColor: Colors.white,
          elevation: 0,
        ),
        cardTheme: CardThemeData(
          color: p.surfaceDark,
          elevation: 1,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.textOnPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: p.primary,
            foregroundColor: p.textOnPrimary,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: p.surfaceDark,
          indicatorColor: p.primary.withValues(alpha: 0.25),
          labelTextStyle: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected ? p.primary : Colors.white70,
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return IconThemeData(
              color: selected ? p.primary : Colors.white70,
            );
          }),
        ),
      );
}