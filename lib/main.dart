import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config/app_config.dart';
import 'firebase_options.dart';
import 'services/webuntis_service.dart';
import 'services/notification_service.dart';
import 'services/firebase_auth_service.dart';
import 'services/reminder_service.dart';
import 'screens/login_screen.dart';
import 'screens/home_screen.dart';
import 'screens/messages_screen.dart';
import 'theme/app_theme.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

/// Pre-fetched at startup so HomeScreen doesn't need to fetch it again.
String appVersion = '';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Run Firebase init, SharedPreferences and PackageInfo in parallel —
  // none of them depend on each other.
  final results = await Future.wait([
    Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform),
    SharedPreferences.getInstance(),
    PackageInfo.fromPlatform(),
  ]);

  final prefs = results[1] as SharedPreferences;
  final info = results[2] as PackageInfo;

  appVersion = info.version;

  final saved = prefs.getString('themeMode') ?? 'system';
  AppTheme.themeNotifier.value = _themeModeFrom(saved);

  // Initialize notification service (FCM permissions + listeners)
  await NotificationService().initialize();
  await ReminderService().initialize();

  runApp(const PockyhApp());
}

ThemeMode _themeModeFrom(String value) {
  switch (value) {
    case 'light':  return ThemeMode.light;
    case 'dark':   return ThemeMode.dark;
    default:       return ThemeMode.system;
  }
}

class PockyhApp extends StatefulWidget {
  const PockyhApp({super.key});

  @override
  State<PockyhApp> createState() => _PockyhAppState();
}

class _PockyhAppState extends State<PockyhApp> {
  @override
  void initState() {
    super.initState();
    AppTheme.themeNotifier.addListener(_onThemeChanged);
  }

  @override
  void dispose() {
    AppTheme.themeNotifier.removeListener(_onThemeChanged);
    super.dispose();
  }

  void _onThemeChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: AppTheme.themeNotifier.value,
      navigatorKey: navigatorKey,
      builder: (context, child) {
        AppTheme.currentBrightness = Theme.of(context).brightness;
        return child!;
      },
      home: const SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _fade = CurvedAnimation(parent: _anim, curve: Curves.easeOut);
    _anim.forward();
    _tryRestoreSession();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  static void _showNewMessageBanner(
    BuildContext context,
    int count,
    String? subject,
    WebUntisService service,
  ) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final text = count == 1
        ? 'Neue Mitteilung: ${subject ?? ''}'
        : '$count neue Mitteilungen';

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(CupertinoIcons.bell_fill, color: Colors.white, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Anzeigen',
          textColor: Colors.white,
          onPressed: () {
            navigatorKey.currentState?.push(
              CupertinoPageRoute(
                builder: (_) => MessagesScreen(service: service),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _tryRestoreSession() async {
    final service = WebUntisService();
    final restored = await service.restoreSession();

    if (!mounted) return;

    // Kick off profile image fetch in background — doesn't block navigation.
    if (restored) {
      service.fetchProfileImage().ignore();
      // Sign in to Firebase with the restored WebUntis username + Klasse
      if (service.username != null) {
        FirebaseAuthService.instance
            .signInAnonymously(
              service.username!,
              klasseId: service.klasseId,
              klasseName: service.klasseName,
            )
            .then((_) {
              final kid = service.klasseId;
              final kname = service.klasseName;
              if (kid != null && kname != null && kname.isNotEmpty) {
                ReminderService()
                    .autoJoinOrCreateWebuntisClass(kname, kid)
                    .catchError((e) => debugPrint('[Restore] Auto-Klasse Fehler: $e'));
              }
            })
            .catchError((e) => debugPrint('[Restore] Firebase auth failed: $e'));
      }
      // Start polling for new messages
      final notifService = NotificationService();
      notifService.startPolling(service);
      notifService.onNewMessages = (count, subject) {
        final ctx = navigatorKey.currentContext;
        if (ctx != null) {
          _showNewMessageBanner(ctx, count, subject, service);
        }
      };
    }

    final target = restored
        ? HomeScreen(service: service)
        : const LoginScreen();

    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => target,
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Center(
        child: FadeTransition(
          opacity: _fade,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppTheme.accent, AppTheme.accentSoft],
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Image.asset(
                    'assets/icons/POKYH_icon.png',
                    width: 48,
                    height: 48,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                AppConfig.appName,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 32),
              const CupertinoActivityIndicator(radius: 12),
            ],
          ),
        ),
      ),
    );
  }
}
