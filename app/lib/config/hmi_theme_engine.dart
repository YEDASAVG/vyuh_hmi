import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dashboard_config.dart';

/// Generates a [ThemeData] from a [ThemeConfig].
///
/// Replaces the static HmiTheme / HmiColors with config-driven values
/// so different JSON configs produce different visual themes.
class HmiThemeEngine {
  final ThemeConfig colors;

  const HmiThemeEngine(this.colors);

  ThemeData build() {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.dark(
        surface: colors.surface,
        primary: colors.accent,
        secondary: colors.info,
        error: colors.danger,
        onSurface: colors.textPrimary,
        onPrimary: colors.background,
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.surfaceBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: colors.background,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: colors.textPrimary,
        ),
        iconTheme: IconThemeData(color: colors.textSecondary),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: colors.surface,
        selectedItemColor: colors.accent,
        unselectedItemColor: colors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(
        color: colors.surfaceBorder,
        thickness: 1,
        space: 0,
      ),
      textTheme: _buildTextTheme(),
    );
  }

  TextTheme _buildTextTheme() {
    return TextTheme(
      displayLarge: GoogleFonts.dmMono(
        fontSize: 48,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      displayMedium: GoogleFonts.dmMono(
        fontSize: 36,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      displaySmall: GoogleFonts.dmMono(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      headlineMedium: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: colors.textPrimary,
      ),
      titleMedium: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      titleSmall: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textSecondary,
      ),
      bodyMedium: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: colors.textPrimary,
      ),
      bodySmall: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: colors.textSecondary,
      ),
      labelLarge: GoogleFonts.dmMono(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      labelMedium: GoogleFonts.dmMono(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      labelSmall: GoogleFonts.dmMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: colors.textMuted,
      ),
    );
  }
}

/// Provides runtime access to the active [ThemeConfig].
///
/// Widgets that reference HmiColors directly can use this instead
/// to get config-driven colors.
class ActiveTheme extends InheritedWidget {
  final ThemeConfig colors;

  const ActiveTheme({
    super.key,
    required this.colors,
    required super.child,
  });

  static ThemeConfig of(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ActiveTheme>();
    return widget?.colors ?? const ThemeConfig();
  }

  /// Try to get theme without establishing dependency (for init code).
  static ThemeConfig? maybeOf(BuildContext context) {
    final widget = context.dependOnInheritedWidgetOfExactType<ActiveTheme>();
    return widget?.colors;
  }

  @override
  bool updateShouldNotify(ActiveTheme oldWidget) =>
      colors != oldWidget.colors;
}
