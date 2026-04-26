enum AppThemeMode { system, light, dark }

/// Central configuration for all app-wide constants.
///
/// Nothing school- or service-specific should be hardcoded in widgets.
/// Add every string, URL, or tunable value here so the app can be adapted
/// to a different school or deployment by editing this single file.
class AppConfig {
  AppConfig._();

  // ── Identity ───────────────────────────────────────────────────────────────
  static const String appName = 'POKYH';
  static const String schoolName = 'LBS Brixen';

  // ── Contacts / Links ───────────────────────────────────────────────────────
  static const String feedbackEmail = 'contact@pokyh.com';
  static const String githubOwner = 'bedchem';
  static const String githubRepo = 'POKYH';
  static const String githubUrl = 'https://github.com/$githubOwner/$githubRepo';

  // ── API endpoints ──────────────────────────────────────────────────────────
  static const String mensaApiUrl = 'https://mensa.plattnericus.dev/mensa.json';

  // ── WebUntis ───────────────────────────────────────────────────────────────
  static const String webUntisBaseUrl =
      'https://lbs-brixen.webuntis.com/WebUntis';
  static const String webUntisSchool = 'lbs-brixen';
  static const String webUntisSchoolNameCookie = '_bGJzLWJyaXhlbg==';

  // ── Locale strings (German) ────────────────────────────────────────────────
  /// Abbreviated weekday names Mon–Fri (index 0 = Monday).
  static const List<String> dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

  /// Abbreviated month names (index 0 = January).
  static const List<String> monthLabels = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  // ── School year ────────────────────────────────────────────────────────────
  /// Returns the current school year label, e.g. "2025/2026".
  /// School year starts in September (month 9).
  static String get currentSchoolYear {
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    return '$startYear/${startYear + 1}';
  }

  // ── Copyright ──────────────────────────────────────────────────────────────
  /// Returns the current year for the copyright notice.
  static int get copyrightYear => DateTime.now().year;

  // ── Fallback break windows ─────────────────────────────────────────────────
  /// Used only when the TimeGrid from WebUntis is unavailable.
  /// Format: WebUntis time integers (e.g. 1020 = 10:20).
  static const List<({int start, int end})> defaultBreakWindows = [
    (start: 1020, end: 1030),
    (start: 1455, end: 1505),
  ];

  // ── Timeouts / Cache TTLs ──────────────────────────────────────────────────
  static const Duration networkTimeout = Duration(seconds: 15);
  static const Duration timetableCacheTTL = Duration(minutes: 10);
  static const Duration gradesCacheTTL = Duration(minutes: 5);
  static const Duration updateCheckTimeout = Duration(seconds: 10);
  static const Duration downloadTimeout = Duration(minutes: 10);
  static const Duration mensaTimeout = Duration(seconds: 6);
  static const Duration messagesCacheTTL = Duration(minutes: 5);
  static const Duration messagesCheckInterval = Duration(minutes: 5);

  // ── Update installers ──────────────────────────────────────────────────────
  /// Ordered iOS installer targets: first match that can be opened is used.
  static const List<String> iosInstallerSchemes = ['sidestore', 'altstore'];

  static Uri buildIosInstallerUri(String scheme, String ipaUrl) {
    return Uri.parse('$scheme://install?url=${Uri.encodeComponent(ipaUrl)}');
  }
}
