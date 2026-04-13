import 'package:flutter/material.dart';

class AppTheme {
  // ── Runtime brightness (set by MaterialApp.builder) ─────────────────────
  static Brightness currentBrightness = Brightness.dark;
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

  static bool get _isDark => currentBrightness == Brightness.dark;

  // ── Adaptive palette ────────────────────────────────────────────────────
  static Color get bg =>
      _isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
  static Color get surface =>
      _isDark ? const Color(0xFF1C1C1E) : const Color(0xFFFFFFFF);
  static Color get card =>
      _isDark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7);
  static Color get cardAlt =>
      _isDark ? const Color(0xFF1C1C1E) : const Color(0xFFE5E5EA);
  static Color get border =>
      _isDark ? const Color(0xFF38383A) : const Color(0xFFD1D1D6);
  static Color get separator =>
      _isDark ? const Color(0xFF48484A) : const Color(0xFFC6C6C8);
  static Color get textPrimary =>
      _isDark ? const Color(0xFFFFFFFF) : const Color(0xFF000000);
  static Color get textSecondary =>
      _isDark ? const Color(0xFF98989D) : const Color(0xFF8E8E93);
  static Color get textTertiary =>
      _isDark ? const Color(0xFF636366) : const Color(0xFFAEAEB2);

  // ── Fixed colors (same in both themes) ──────────────────────────────────
  static const Color accent = Color(0xFF0A84FF);
  static const Color accentSoft = Color(0xFF5E5CE6);
  static const Color tint = Color(0xFF30D158);
  static const Color success = Color(0xFF30D158);
  static const Color warning = Color(0xFFFFD60A);
  static const Color danger = Color(0xFFFF453A);
  static const Color orange = Color(0xFFFF9F0A);

  // ── Lesson colors ──────────────────────────────────────────────────────
  static const Map<String, Color> _subjectColorMap = {
    'D': Color(0xFF5AA0E8),
    'M': Color(0xFF4ED87A),
    'IT': Color.fromARGB(255, 255, 0, 242),
    'Bew.Sport': Color(0xFFAA8EE0),
    'ENGL': Color(0xFF3DC4CE),
    'R': Color(0xFFE8B84A),
    'M5-M7': Color(0xFFE08899),
    'M8': Color(0xFFE89E6E),
    'Re-Wiku': Color(0xFF6AB87A),
  };

  static Color colorForSubject(String name) {
    if (name.isEmpty) return const Color.fromARGB(255, 48, 137, 209);
    return _subjectColorMap[name] ?? const Color(0xFF7A7A8A);
  }

  // ── ThemeData ──────────────────────────────────────────────────────────
  static ThemeData dark() {
    return _build(Brightness.dark);
  }

  static ThemeData light() {
    return _build(Brightness.light);
  }

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final bgColor = isDark ? const Color(0xFF000000) : const Color(0xFFF2F2F7);
    final surfaceColor = isDark
        ? const Color(0xFF1C1C1E)
        : const Color(0xFFFFFFFF);
    final cardColor = isDark
        ? const Color(0xFF2C2C2E)
        : const Color(0xFFF2F2F7);
    final txtPrimary = isDark
        ? const Color(0xFFFFFFFF)
        : const Color(0xFF000000);
    final txtSecondary = isDark
        ? const Color(0xFF98989D)
        : const Color(0xFF8E8E93);
    final txtTertiary = isDark
        ? const Color(0xFF636366)
        : const Color(0xFFAEAEB2);

    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bgColor,
      fontFamily: '.SF Pro Text',
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: accent,
        onPrimary: Colors.white,
        secondary: accentSoft,
        onSecondary: Colors.white,
        surface: surfaceColor,
        onSurface: txtPrimary,
        error: danger,
        onError: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bgColor,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleTextStyle: TextStyle(
          color: txtPrimary,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        iconTheme: const IconThemeData(color: accent),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardColor,
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
        labelStyle: TextStyle(color: txtSecondary, fontSize: 15),
        hintStyle: TextStyle(color: txtTertiary, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: accent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: surfaceColor,
        selectedItemColor: accent,
        unselectedItemColor: txtTertiary,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w400,
        ),
      ),
    );
  }
}
