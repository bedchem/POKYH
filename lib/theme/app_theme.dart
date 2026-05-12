import 'package:flutter/material.dart';

class AppTheme {
  static final themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.dark);

  // ── Fixed colors (same in both themes) ──────────────────────────────────
  static const Color accent = Color(0xFF6366F1);
  static const Color accentSoft = Color(0xFF8B5CF6);
  static const Color tint = Color(0xFF10B981);
  static const Color success = Color(0xFF10B981);
  static const Color successMid = Color(0xFF10B981);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFEF4444);
  static const Color orange = Color(0xFFF97316);

  // ── Lesson colors ──────────────────────────────────────────────────────
  static const Map<String, Color> _subjectColorMap = {
    'D': Color(0xFF5AA0E8),
    'M': Color(0xFF4ED87A),
    'IT': Color.fromARGB(255, 231, 59, 223),
    'Bew.Sport': Color(0xFFAA8EE0),
    'ENGL': Color(0xFF3DC4CE),
    'R': Color.fromARGB(255, 198, 232, 74),
    'M5-M7': Color(0xFFE08899),
    'M8': Color(0xFFE89E6E),
    'Re-Wiku': Color(0xFF6AB87A),
  };

  /// Returns a color for a subject name.
  /// Uses the predefined map first; unknown subjects get a deterministic
  /// color derived from their name so the same subject always has the
  /// same color regardless of which school uses the app.
  static Color colorForSubject(String name) {
    if (name.isEmpty) return const Color(0xFF5AA0E8);
    final known = _subjectColorMap[name];
    if (known != null) return known;
    // Deterministic hue from subject name — consistent across sessions.
    final hash = name.codeUnits.fold(0, (h, c) => (h * 31 + c) & 0xFFFFFFFF);
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1.0, hue, 0.50, 0.52).toColor();
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
    final bgColor = isDark ? const Color(0xFF09090C) : const Color(0xFFF0F0F5);
    final surfaceColor = isDark
        ? const Color(0xFF111116)
        : const Color(0xFFFFFFFF);
    final cardColor = isDark
        ? const Color(0xFF18181E)
        : const Color(0xFFF7F7FC);
    final txtPrimary = isDark
        ? const Color(0xFFF0F0F8)
        : const Color(0xFF0A0A12);
    final txtSecondary = isDark
        ? const Color(0xFF8A8A9C)
        : const Color(0xFF65657A);
    final txtTertiary = isDark
        ? const Color(0xFF52525F)
        : const Color(0xFFA0A0B4);

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

// ── Context extension for adaptive colors ────────────────────────────────────
// Using Theme.of(context) registers the widget as a Theme dependent so it
// automatically rebuilds whenever the theme changes (dark ↔ light ↔ system).
extension AppColors on BuildContext {
  bool get _appIsDark => Theme.of(this).brightness == Brightness.dark;

  Color get appBg =>
      _appIsDark ? const Color(0xFF09090C) : const Color(0xFFF0F0F5);
  Color get appSurface =>
      _appIsDark ? const Color(0xFF111116) : const Color(0xFFFFFFFF);
  Color get appCard =>
      _appIsDark ? const Color(0xFF18181E) : const Color(0xFFF7F7FC);
  Color get appCardAlt =>
      _appIsDark ? const Color(0xFF20202A) : const Color(0xFFEBEBF2);
  Color get appBorder =>
      _appIsDark ? const Color(0xFF222230) : const Color(0xFFE2E2ED);
  Color get appSeparator =>
      _appIsDark ? const Color(0xFF1C1C28) : const Color(0xFFDADADF);
  Color get appTextPrimary =>
      _appIsDark ? const Color(0xFFF0F0F8) : const Color(0xFF0A0A12);
  Color get appTextSecondary =>
      _appIsDark ? const Color(0xFF8A8A9C) : const Color(0xFF65657A);
  Color get appTextTertiary =>
      _appIsDark ? const Color(0xFF52525F) : const Color(0xFFA0A0B4);
}
