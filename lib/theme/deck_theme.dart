import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class DeckColors {
  // Base Surfaces (Industrial Dark / Chassis Palette)
  static const Color surfaceCore = Color(0xFF090A0E); // Deep Obsidian
  static const Color surfaceRack = Color(0xFF11141C); // Rack Chassis
  static const Color surfaceInset = Color(0xFF050608); // Terminal Bay Inset
  static const Color surfaceElevated = Color(0xFF181D27); // Keypad & Dialogs
  static const Color surfaceHighlight = Color(0xFF222937);

  // Structural Seams & Dividers
  static const Color borderSubtle = Color(0xFF1E2532);
  static const Color borderMedium = Color(0xFF2C3546);
  static const Color borderActive = Color(0xFFF97316); // Industrial Safety Orange

  // Signal & Status Indicators
  static const Color accentOrange = Color(0xFFF97316); // Active Target / Action
  static const Color phosphorGreen = Color(0xFF10B981); // Live Peer / Healthy
  static const Color cautionAmber = Color(0xFFF59E0B); // Standby / LapDog Away
  static const Color meshCyan = Color(0xFF06B6D4); // Tailscale Direct Route
  static const Color alertCrimson = Color(0xFFEF4444); // Error / Critical Alert
  static const Color offlineSteel = Color(0xFF64748B); // Offline Host

  // Typography Palette
  static const Color textHigh = Color(0xFFF8FAFC); // Primary high-contrast
  static const Color textMid = Color(0xFF94A3B8); // Secondary telemetry
  static const Color textMuted = Color(0xFF64748B); // Dividers / units
  static const Color textTerminal = Color(0xFF34D399); // Terminal phosphor green
}

class DeckTheme {
  static ThemeData get darkTheme {
    final baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: DeckColors.surfaceCore,
      primaryColor: DeckColors.accentOrange,
      colorScheme: const ColorScheme.dark(
        surface: DeckColors.surfaceRack,
        primary: DeckColors.accentOrange,
        secondary: DeckColors.phosphorGreen,
        error: DeckColors.alertCrimson,
      ),
      textTheme: GoogleFonts.ibmPlexSansTextTheme(baseTextTheme).copyWith(
        titleLarge: GoogleFonts.spaceGrotesk(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: DeckColors.textHigh,
        ),
        titleMedium: GoogleFonts.spaceGrotesk(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
          color: DeckColors.textHigh,
        ),
        labelLarge: GoogleFonts.jetBrainsMono(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.6,
          color: DeckColors.textHigh,
        ),
        labelSmall: GoogleFonts.jetBrainsMono(
          fontSize: 10,
          fontWeight: FontWeight.w500,
          letterSpacing: 0.4,
          color: DeckColors.textMid,
        ),
        bodyMedium: GoogleFonts.ibmPlexSans(
          fontSize: 13,
          color: DeckColors.textMid,
        ),
        bodySmall: GoogleFonts.jetBrainsMono(
          fontSize: 11,
          color: DeckColors.textMuted,
        ),
      ),
      cardTheme: CardTheme(
        color: DeckColors.surfaceRack,
        elevation: 0,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderSubtle, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
        margin: EdgeInsets.zero,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DeckColors.surfaceInset,
        labelStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: DeckColors.textMid),
        hintStyle: GoogleFonts.jetBrainsMono(fontSize: 12, color: DeckColors.textMuted),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: DeckColors.borderSubtle, width: 1),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: DeckColors.borderActive, width: 1),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: DeckColors.surfaceElevated,
        contentTextStyle: GoogleFonts.jetBrainsMono(
          fontSize: 12,
          color: DeckColors.textHigh,
        ),
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: DeckColors.borderMedium, width: 1),
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    );
  }
}
