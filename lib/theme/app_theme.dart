import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class AppTheme {
  // ── Palette ──────────────────────────────────────────────────────────────
  static const Color bg = Color(0xFF000000);
  static const Color surface = Color(0xFF1C1C1E);
  static const Color card = Color(0xFF2C2C2E);
  static const Color cardAlt = Color(0xFF1C1C1E);
  static const Color border = Color(0xFF38383A);
  static const Color separator = Color(0xFF48484A);

  static const Color accent = Color(0xFF0A84FF);     // iOS Blue
  static const Color accentSoft = Color(0xFF5E5CE6);  // iOS Indigo
  static const Color tint = Color(0xFF30D158);         // iOS Green

  static const Color textPrimary = Color(0xFFFFFFFF);
  static const Color textSecondary = Color(0xFF98989D);
  static const Color textTertiary = Color(0xFF636366);

  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color danger = Color(0xFFFF453A);
  static const Color orange = Color(0xFFFF9F0A);

  // ── Lesson colors (pastel, iOS-inspired) ────────────────────────────────
// ── Lesson colors ────────────────────────────────────────────────────────
static const Map<String, Color> _subjectColorMap = {
  'D':         Color(0xFF5AA0E8), // Stahlblau
  'M':         Color(0xFF4ED87A), // Salbeigrün
  'IT':        Color(0xFFD4855A), // Terrakotta
  'Bew.Sport': Color(0xFFAA8EE0), // Lavendel
  'ENGL':      Color(0xFF3DC4CE), // Türkis
  'R':         Color(0xFFE8B84A), // Amber
  'M5-M7':     Color(0xFFE08899), // Altrosa
  'M8':        Color(0xFFE89E6E), // Lachs
  'Re-Wiku':   Color(0xFF6AB87A), // Moosgrün
};

static Color colorForSubject(String name) {
  if (name.isEmpty) return const Color.fromARGB(255, 48, 137, 209);
  return _subjectColorMap[name] ?? const Color(0xFF7A7A8A);
}
  // ── Theme ───────────────────────────────────────────────────────────────
  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: bg,
      fontFamily: '.SF Pro Text',
      colorScheme: const ColorScheme.dark(
        primary: accent,
        surface: surface,
        onPrimary: Colors.white,
        onSurface: textPrimary,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        iconTheme: IconThemeData(color: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: card,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: accent, width: 1),
        ),
        labelStyle: const TextStyle(color: textSecondary, fontSize: 15),
        hintStyle: const TextStyle(color: textTertiary, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1C1C1E),
        selectedItemColor: accent,
        unselectedItemColor: textTertiary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w500),
        unselectedLabelStyle: TextStyle(fontSize: 10, fontWeight: FontWeight.w400),
      ),
    );
  }
}
