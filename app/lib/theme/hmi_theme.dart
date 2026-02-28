import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'hmi_colors.dart';

/// Industrial dark HMI theme.
/// Fonts: Outfit (display/body), DM Mono (monospace numbers).
class HmiTheme {
  static ThemeData get dark {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: HmiColors.void_,
      colorScheme: const ColorScheme.dark(
        surface: HmiColors.surface,
        primary: HmiColors.accent,
        secondary: HmiColors.info,
        error: HmiColors.danger,
        onSurface: HmiColors.textPrimary,
        onPrimary: HmiColors.void_,
      ),
      cardTheme: CardThemeData(
        color: HmiColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: HmiColors.surfaceBorder, width: 1),
        ),
        margin: EdgeInsets.zero,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: HmiColors.void_,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: HmiColors.textPrimary,
        ),
        iconTheme: const IconThemeData(color: HmiColors.textSecondary),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: HmiColors.surface,
        selectedItemColor: HmiColors.accent,
        unselectedItemColor: HmiColors.textMuted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: const DividerThemeData(
        color: HmiColors.surfaceBorder,
        thickness: 1,
        space: 0,
      ),
      textTheme: _buildTextTheme(),
    );
  }

  static TextTheme _buildTextTheme() {
    return TextTheme(
      // Hero numbers (gauge center value).
      displayLarge: GoogleFonts.dmMono(
        fontSize: 48,
        fontWeight: FontWeight.w500,
        color: HmiColors.textPrimary,
      ),
      displayMedium: GoogleFonts.dmMono(
        fontSize: 36,
        fontWeight: FontWeight.w500,
        color: HmiColors.textPrimary,
      ),
      displaySmall: GoogleFonts.dmMono(
        fontSize: 28,
        fontWeight: FontWeight.w500,
        color: HmiColors.textPrimary,
      ),
      // Section headings.
      headlineMedium: GoogleFonts.outfit(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: HmiColors.textPrimary,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: HmiColors.textPrimary,
      ),
      // Card titles.
      titleMedium: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: HmiColors.textSecondary,
      ),
      titleSmall: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: HmiColors.textSecondary,
      ),
      // Body text.
      bodyMedium: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w400,
        color: HmiColors.textPrimary,
      ),
      bodySmall: GoogleFonts.outfit(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        color: HmiColors.textSecondary,
      ),
      // Monospace values.
      labelLarge: GoogleFonts.dmMono(
        fontSize: 20,
        fontWeight: FontWeight.w500,
        color: HmiColors.textPrimary,
      ),
      labelMedium: GoogleFonts.dmMono(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        color: HmiColors.textPrimary,
      ),
      labelSmall: GoogleFonts.dmMono(
        fontSize: 11,
        fontWeight: FontWeight.w400,
        color: HmiColors.textMuted,
      ),
    );
  }
}
