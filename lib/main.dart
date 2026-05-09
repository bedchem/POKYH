import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'services/webuntis_service.dart';
import 'services/notification_service.dart';
import 'services/reminder_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pre-fetched at startup so HomeScreen doesn't need to fetch it again.
String appVersion = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: '.env');

  final results = await Future.wait([
    SharedPreferences.getInstance(),
    PackageInfo.fromPlatform(),
  ]);

  final prefs = results[0] as SharedPreferences;
  final info = results[1] as PackageInfo;
  appVersion = info.version;

  final saved = prefs.getString('themeMode') ?? 'system';
  AppTheme.themeNotifier.value = _themeModeFrom(saved);

  await NotificationService().initialize();
  await ReminderService().initialize();

  // Restore session before runApp — the OS LaunchScreen covers this async work.
  // The first rendered Flutter frame shows the correct screen with no loading needed.
  final service = WebUntisService();
  final sessionRestored = await service.restoreSession();

  runApp(PockyhApp(service: service, sessionRestored: sessionRestored));
}

ThemeMode _themeModeFrom(String value) {
  switch (value) {
    case 'light':
      return ThemeMode.light;
    case 'dark':
      return ThemeMode.dark;
    default:
      return ThemeMode.system;
  }
}

// Compute themes once at startup — not on every rebuild.
final _lightTheme = AppTheme.light();
final _darkTheme = AppTheme.dark();

class PockyhApp extends StatelessWidget {
  final WebUntisService service;
  final bool sessionRestored;

  const PockyhApp({
    super.key,
    required this.service,
    required this.sessionRestored,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeNotifier,
      builder: (_, mode, __) => MaterialApp(
        title: AppConfig.appName,
        debugShowCheckedModeBanner: false,
        theme: _lightTheme,
        darkTheme: _darkTheme,
        themeMode: mode,
        navigatorKey: navigatorKey,
        home: sessionRestored
            ? HomeScreen(service: service, fromRestore: true)
            : const LoginScreen(),
      ),
    );
  }
}
