import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DeckColors {
  // Refined Dark-First Palette
  static const Color background = Color(0xFF11151B);
  static const Color surfaceSecondary = Color(0xFF171D25);
  static const Color surfaceElevated = Color(0xFF1D2530);
  static const Color surfaceHighlight = Color(0xFF252F3D);

  // Subtle Structural Borders
  static const Color borderSubtle = Color(0xFF303A47);
  static const Color borderMedium = Color(0xFF3D4A5C);

  // Typography Palette
  static const Color primaryText = Color(0xFFF1F3F5);
  static const Color secondaryText = Color(0xFFA0AAB8);
  static const Color mutedText = Color(0xFF768294);

  // Intentional Accent & Status Semantics
  static const Color primaryAccent = Color(0xFFE89A50); // Warm signature amber
  static const Color healthy = Color(0xFF36B58E); // Mint emerald
  static const Color informational = Color(0xFF47AFC5); // Cyan blue
  static const Color warning = Color(0xFFE5B45D); // Caution amber
  static const Color error = Color(0xFFE16C70); // Coral red
  static const Color terminalText = Color(0xFF4ADE80); // Phosphor green

  // Legacy aliases for backward compatibility with existing components
  static const Color surfaceCore = background;
  static const Color surfaceRack = surfaceSecondary;
  static const Color surfaceInset = surfaceElevated;
  static const Color accentOrange = primaryAccent;
  static const Color phosphorGreen = healthy;
  static const Color cautionAmber = warning;
  static const Color alertCrimson = error;
  static const Color meshCyan = informational;
  static const Color textHigh = primaryText;
  static const Color textMid = secondaryText;
  static const Color textMuted = mutedText;
  static const Color textTerminal = terminalText;
  static const Color borderActive = primaryAccent;
  static const Color offlineSteel = mutedText;
}

class DeckTheme {
  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DeckColors.background,
      primaryColor: DeckColors.primaryAccent,
      colorScheme: const ColorScheme.dark(
        surface: DeckColors.surfaceSecondary,
        primary: DeckColors.primaryAccent,
        secondary: DeckColors.healthy,
        error: DeckColors.error,
        onSurface: DeckColors.primaryText,
        onPrimary: DeckColors.background,
      ),
      textTheme: GoogleFonts.interTextTheme(baseTextTheme).copyWith(
        headlineMedium: GoogleFonts.inter(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: DeckColors.primaryText,
          letterSpacing: -0.3,
        ),
        titleLarge: GoogleFonts.inter(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: DeckColors.primaryText,
          letterSpacing: -0.2,
        ),
        titleMedium: GoogleFonts.inter(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: DeckColors.primaryText,
        ),
        titleSmall: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeckColors.primaryText,
        ),
        bodyLarge: GoogleFonts.inter(
          fontSize: 15,
          fontWeight: FontWeight.w400,
          color: DeckColors.primaryText,
        ),
        bodyMedium: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w400,
          color: DeckColors.secondaryText,
          height: 1.4,
        ),
        bodySmall: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w400,
          color: DeckColors.mutedText,
        ),
        labelLarge: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: DeckColors.primaryText,
        ),
        labelMedium: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: DeckColors.secondaryText,
        ),
        labelSmall: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          fontWeight: FontWeight.w500,
          color: DeckColors.secondaryText,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DeckColors.surfaceSecondary,
        indicatorColor: DeckColors.surfaceHighlight,
        elevation: 0,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: DeckColors.primaryAccent,
            );
          }
          return GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: DeckColors.mutedText,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DeckColors.primaryAccent, size: 22);
          }
          return const IconThemeData(color: DeckColors.mutedText, size: 22);
        }),
      ),
      cardTheme: CardThemeData(
        color: DeckColors.surfaceSecondary,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(12),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DeckColors.surfaceElevated,
        labelStyle: GoogleFonts.inter(fontSize: 13, color: DeckColors.secondaryText),
        hintStyle: GoogleFonts.inter(fontSize: 13, color: DeckColors.mutedText),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: DeckColors.primaryAccent, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DeckColors.surfaceElevated,
        contentTextStyle: GoogleFonts.inter(
          fontSize: 13,
          color: DeckColors.primaryText,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}
