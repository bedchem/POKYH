import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../config/app_config.dart';
import '../main.dart' show appVersion;
import '../services/dish_service.dart';
import '../services/firebase_auth_service.dart';
import '../services/webuntis_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';

bool get _isIOS => Platform.isIOS;

class ProfileScreen extends StatefulWidget {
  final WebUntisService service;
  final VoidCallback onLogout;
  const ProfileScreen({
    super.key,
    required this.service,
    required this.onLogout,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _clearingCache = false;
  bool _checkingUpdate = false;
  // appVersion is pre-fetched at startup in main.dart — no async call needed.
  String get _appVersion => appVersion.isNotEmpty ? appVersion : '?.?.?';

  // Einstellungen
  String _themeMode = 'system';
  String _language = 'de';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _themeMode = prefs.getString('themeMode') ?? 'system';
      _language = prefs.getString('language') ?? 'de';
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  void _applyTheme(String mode) {
    setState(() => _themeMode = mode);
    _save('themeMode', mode);
    switch (mode) {
      case 'light':
        AppTheme.themeNotifier.value = ThemeMode.light;
      case 'dark':
        AppTheme.themeNotifier.value = ThemeMode.dark;
      default:
        AppTheme.themeNotifier.value = ThemeMode.system;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Logout
  // ──────────────────────────────────────────────────────────────────────────
  void _confirmLogout() {
    if (_isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Abmelden'),
          content: const Text('Möchtest du dich wirklich abmelden?'),
          actions: [
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            CupertinoDialogAction(
              isDestructiveAction: true,
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                widget.onLogout();
              },
              child: const Text('Abmelden'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            'Abmelden',
            style: TextStyle(color: context.appTextPrimary),
          ),
          content: Text(
            'Möchtest du dich wirklich abmelden?',
            style: TextStyle(color: context.appTextSecondary),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Abbrechen'),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
                widget.onLogout();
              },
              child: const Text(
                'Abmelden',
                style: TextStyle(color: AppTheme.danger),
              ),
            ),
          ],
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Cache leeren
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      await Future.wait([
        DishService().clearCache(),
        widget.service.clearLocalCaches(),
        DefaultCacheManager().emptyCache(),
      ]);
      imageCache.clear();
      imageCache.clearLiveImages();
      if (!mounted) return;
      _showToast('Cache geleert');
    } catch (_) {
      if (mounted) _showToast('Fehler beim Leeren');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  void _showToast(String message) {
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (ctx) => _ToastOverlay(message: message),
    );
    overlay.insert(entry);
    Future.delayed(const Duration(seconds: 2), () => entry.remove());
  }

  void _copyUserId() {
    final id = widget.service.studentId?.toString() ?? '';
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    _showToast('ID kopiert: $id');
  }

  void _copyStableUid() {
    final uid =
        FirebaseAuthService.instance.stableUid ??
        FirebaseAuthService.instance.userId ??
        '';
    if (uid.isEmpty) return;
    Clipboard.setData(ClipboardData(text: uid));
    _showToast(
      'UID kopiert: ${uid.length > 12 ? '${uid.substring(0, 12)}…' : uid}',
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Update Check
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _checkForUpdate() async {
    if (_checkingUpdate) return;
    setState(() => _checkingUpdate = true);
    try {
      final found = await UpdateService.checkForUpdate(
        context,
        source: UpdateCheckSource.settingsManual,
      );
      if (mounted && !found) {
        _showToast('Kein Update verfügbar');
      }
    } catch (_) {
      if (mounted) _showToast('Update‑Prüfung fehlgeschlagen');
    } finally {
      if (mounted) setState(() => _checkingUpdate = false);
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Feedback per E‑Mail
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppConfig.feedbackEmail,
      queryParameters: {
        'subject': '[${AppConfig.appName}] Feedback',
        'body':
            '\n\n---\nVersion: $_appVersion\nSchule: ${AppConfig.schoolName}',
      },
    );

    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      _showToast('Mail-App nicht verfügbar');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GitHub öffnen
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _openGitHub() async {
    final uri = Uri.parse(AppConfig.githubUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showToast('Browser nicht verfügbar');
    }
  }

  void _showLegalLinks() {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.appSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: context.appBorder.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Rechtliches',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                ),
              ),
              const SizedBox(height: 20),
              _LegalButton(
                icon: _isIOS
                    ? CupertinoIcons.doc_text
                    : Icons.description_outlined,
                title: 'Impressum',
                subtitle: 'pokyh.com/legal?view=impressum',
                onTap: () async {
                  final uri = Uri.parse(
                    'https://pokyh.com/legal?view=impressum',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
              const SizedBox(height: 10),
              _LegalButton(
                icon: _isIOS
                    ? CupertinoIcons.lock_shield
                    : Icons.privacy_tip_outlined,
                title: 'Datenschutz',
                subtitle: 'pokyh.com/legal?view=datenschutz',
                onTap: () async {
                  final uri = Uri.parse(
                    'https://pokyh.com/legal?view=datenschutz',
                  );
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showAbout() {
    if (_isIOS) {
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: Text(AppConfig.appName),
          content: Text(
            'Version $_appVersion\n\n'
            'Die All-in-One Schul-App für die ${AppConfig.schoolName}.\n'
            'Made with <3 by Plattnericus & Ryhox\n\n'
            '© ${AppConfig.copyrightYear} – MIT Lizenz',
          ),
          actions: [
            CupertinoDialogAction(
              onPressed: _openGitHub,
              child: const Text('GitHub'),
            ),
            CupertinoDialogAction(
              isDefaultAction: true,
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: context.appSurface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Text(
            AppConfig.appName,
            style: TextStyle(color: context.appTextPrimary),
          ),
          content: Text(
            'Version $_appVersion\n\n'
            'Die All‑in‑One Schul‑App für die ${AppConfig.schoolName}.\n\n'
            '© ${AppConfig.copyrightYear} – MIT Lizenz',
            style: TextStyle(color: context.appTextSecondary),
          ),
          actions: [
            TextButton(onPressed: _openGitHub, child: const Text('GitHub')),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Theme‑Auswahl – plattformadaptiv
  // ──────────────────────────────────────────────────────────────────────────
  void _showThemePicker() {
    if (_isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: const Text('Erscheinungsbild'),
          actions: [
            _cupertinoThemeAction(ctx, 'light', 'Hell', CupertinoIcons.sun_max),
            _cupertinoThemeAction(
              ctx,
              'system',
              'Automatisch (System)',
              CupertinoIcons.circle_lefthalf_fill,
            ),
            _cupertinoThemeAction(ctx, 'dark', 'Dunkel', CupertinoIcons.moon),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.appSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Erscheinungsbild',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              _materialThemeAction(
                ctx,
                'light',
                'Hell',
                Icons.light_mode_outlined,
              ),
              _materialThemeAction(
                ctx,
                'system',
                'Automatisch (System)',
                Icons.brightness_auto_outlined,
              ),
              _materialThemeAction(
                ctx,
                'dark',
                'Dunkel',
                Icons.dark_mode_outlined,
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
  }

  CupertinoActionSheetAction _cupertinoThemeAction(
    BuildContext ctx,
    String value,
    String label,
    IconData icon,
  ) {
    return CupertinoActionSheetAction(
      onPressed: () {
        _applyTheme(value);
        Navigator.pop(ctx);
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: _themeMode == value
                ? AppTheme.accent
                : context.appTextPrimary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _themeMode == value
                  ? AppTheme.accent
                  : context.appTextPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _materialThemeAction(
    BuildContext ctx,
    String value,
    String label,
    IconData icon,
  ) {
    final selected = _themeMode == value;
    return ListTile(
      leading: Icon(
        icon,
        color: selected ? AppTheme.accent : context.appTextSecondary,
      ),
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppTheme.accent : context.appTextPrimary,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check, color: AppTheme.accent, size: 20)
          : null,
      onTap: () {
        _applyTheme(value);
        Navigator.pop(ctx);
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sprach‑Auswahl – plattformadaptiv
  // ──────────────────────────────────────────────────────────────────────────
  void _showLanguagePicker() {
    if (_isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (ctx) => CupertinoActionSheet(
          title: const Text('Sprache (Mensa‑Menü)'),
          actions: [
            _cupertinoLangAction(ctx, 'de', 'Deutsch'),
            _cupertinoLangAction(ctx, 'it', 'Italiano'),
            _cupertinoLangAction(ctx, 'en', 'English'),
          ],
          cancelButton: CupertinoActionSheetAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Abbrechen'),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.appSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sprache (Mensa‑Menü)',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
              ),
              _materialLangAction(ctx, 'de', 'Deutsch'),
              _materialLangAction(ctx, 'it', 'Italiano'),
              _materialLangAction(ctx, 'en', 'English'),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
  }

  CupertinoActionSheetAction _cupertinoLangAction(
    BuildContext ctx,
    String code,
    String label,
  ) {
    return CupertinoActionSheetAction(
      onPressed: () {
        setState(() => _language = code);
        _save('language', code);
        Navigator.pop(ctx);
      },
      child: Text(
        label,
        style: TextStyle(
          color: _language == code ? AppTheme.accent : context.appTextPrimary,
        ),
      ),
    );
  }

  Widget _materialLangAction(BuildContext ctx, String code, String label) {
    final selected = _language == code;
    return ListTile(
      title: Text(
        label,
        style: TextStyle(
          color: selected ? AppTheme.accent : context.appTextPrimary,
        ),
      ),
      trailing: selected
          ? Icon(Icons.check, color: AppTheme.accent, size: 20)
          : null,
      onTap: () {
        setState(() => _language = code);
        _save('language', code);
        Navigator.pop(ctx);
      },
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Hilfsfunktionen für Anzeigetexte
  // ──────────────────────────────────────────────────────────────────────────
  String _themeLabel() {
    switch (_themeMode) {
      case 'light':
        return 'Hell';
      case 'dark':
        return 'Dunkel';
      default:
        return 'System';
    }
  }

  String _languageLabel() {
    switch (_language) {
      case 'de':
        return 'Deutsch';
      case 'it':
        return 'Italiano';
      default:
        return 'English';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Section header
  // ──────────────────────────────────────────────────────────────────────────
  SliverToBoxAdapter _sectionHeader(String title) {
    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 20, 10),
        child: Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: context.appTextTertiary,
            letterSpacing: 0.8,
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final username = widget.service.username ?? 'Schüler';

    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _isIOS
                              ? CupertinoIcons.chevron_left
                              : Icons.arrow_back,
                          size: 16,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Profil',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Profilkarte
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        AppTheme.accent.withValues(alpha: 0.12),
                        AppTheme.accentSoft.withValues(alpha: 0.06),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                    ),
                  ),
                  child: Row(
                    children: [
                      _ProfileAvatar(service: widget.service),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              username,
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            _MetaRow(
                              icon: _isIOS
                                  ? CupertinoIcons.building_2_fill
                                  : Icons.school_outlined,
                              text: AppConfig.schoolName,
                            ),
                            if (widget.service.studentId != null) ...[
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: _copyUserId,
                                child: _MetaRow(
                                  icon: _isIOS
                                      ? CupertinoIcons.number
                                      : Icons.tag,
                                  text: 'ID: ${widget.service.studentId}',
                                  hint: 'Tippen zum Kopieren',
                                ),
                              ),
                            ],
                            Builder(
                              builder: (context) {
                                final stableUid =
                                    FirebaseAuthService.instance.stableUid ??
                                    FirebaseAuthService.instance.userId;
                                if (stableUid == null)
                                  return const SizedBox.shrink();
                                final displayUid = stableUid.length > 16
                                    ? '${stableUid.substring(0, 8)}…${stableUid.substring(stableUid.length - 4)}'
                                    : stableUid;
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    GestureDetector(
                                      onTap: _copyStableUid,
                                      child: _MetaRow(
                                        icon: _isIOS
                                            ? CupertinoIcons.person_badge_minus
                                            : Icons.fingerprint,
                                        text: 'UID: $displayUid',
                                        hint: 'Tippen zum Kopieren',
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _StatusDot(),
                                  SizedBox(width: 5),
                                  Text(
                                    'Verbunden',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w500,
                                      color: AppTheme.success,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Einstellungen ──────────────────────────────────
            _sectionHeader('Einstellungen'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.circle_lefthalf_fill
                          : Icons.brightness_auto_outlined,
                      title: 'Erscheinungsbild',
                      subtitle: _themeLabel(),
                      onTap: _showThemePicker,
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: _isIOS ? CupertinoIcons.globe : Icons.language,
                      title: 'Sprache (Mensa)',
                      subtitle: _languageLabel(),
                      onTap: _showLanguagePicker,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── App ────────────────────────────────────────────
            _sectionHeader('App'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.arrow_down_circle
                          : Icons.system_update_outlined,
                      title: 'Nach Updates suchen',
                      subtitle: _appVersion.isNotEmpty
                          ? 'Installiert: v$_appVersion'
                          : 'Version wird geladen…',
                      loading: _checkingUpdate,
                      onTap: _checkingUpdate ? null : _checkForUpdate,
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.trash
                          : Icons.delete_outline,
                      title: 'Cache leeren',
                      subtitle: 'Gespeicherte Daten entfernen',
                      loading: _clearingCache,
                      onTap: _clearingCache ? null : _clearCache,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Info ───────────────────────────────────────────
            _sectionHeader('Info'),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.chat_bubble_text
                          : Icons.feedback_outlined,
                      title: 'Feedback senden',
                      subtitle: 'Idee oder Problem melden',
                      onTap: _sendFeedback,
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.doc_text
                          : Icons.description_outlined,
                      title: 'Rechtliches',
                      subtitle: 'Impressum & Datenschutz',
                      onTap: _showLegalLinks,
                    ),
                    const SizedBox(height: 10),
                    _ActionTile(
                      icon: _isIOS
                          ? CupertinoIcons.info_circle
                          : Icons.info_outline,
                      title: 'Über POKYH',
                      subtitle: _appVersion.isNotEmpty
                          ? 'Version $_appVersion · MIT Lizenz'
                          : 'MIT Lizenz',
                      onTap: _showAbout,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Abmelden ───────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: GestureDetector(
                  onTap: _confirmLogout,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: AppTheme.danger.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _isIOS
                              ? CupertinoIcons.square_arrow_left
                              : Icons.logout,
                          size: 17,
                          color: AppTheme.danger,
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          'Abmelden',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.danger,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 40)),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Hilfs‑Widgets
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileAvatar extends StatefulWidget {
  final WebUntisService service;
  const _ProfileAvatar({required this.service});

  @override
  State<_ProfileAvatar> createState() => _ProfileAvatarState();
}

class _ProfileAvatarState extends State<_ProfileAvatar> {
  @override
  void initState() {
    super.initState();
    if (!widget.service.profileImageFetched) {
      widget.service.fetchProfileImage().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.service.profileImageBytes;
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accent.withValues(alpha: 0.15),
        border: Border.all(
          color: AppTheme.accent.withValues(alpha: 0.3),
          width: 2,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
    child: Text(
      (widget.service.username ?? '?')[0].toUpperCase(),
      style: const TextStyle(
        fontSize: 26,
        fontWeight: FontWeight.w700,
        color: AppTheme.accent,
      ),
    ),
  );
}

class _MetaRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? hint;
  const _MetaRow({required this.icon, required this.text, this.hint});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(
          icon,
          size: 12,
          color: context.appTextTertiary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: context.appTextSecondary),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (hint != null) ...[
          const SizedBox(width: 4),
          Icon(
            _isIOS ? CupertinoIcons.doc_on_clipboard : Icons.content_copy,
            size: 10,
            color: context.appTextTertiary,
          ),
        ],
      ],
    );
  }
}

class _StatusDot extends StatelessWidget {
  const _StatusDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 6,
      height: 6,
      decoration: const BoxDecoration(
        color: AppTheme.success,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appBorder.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: loading
                  ? (_isIOS
                        ? const CupertinoActivityIndicator()
                        : const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: AppTheme.accent,
                            ),
                          ))
                  : Icon(icon, size: 18, color: AppTheme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: context.appTextPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 13,
                      color: context.appTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _isIOS ? CupertinoIcons.chevron_right : Icons.chevron_right,
              size: 16,
              color: context.appTextTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Legal Button ─────────────────────────────────────────────────────────────

class _LegalButton extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _LegalButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: context.appCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: context.appBorder.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 18, color: AppTheme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: context.appTextPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.appTextTertiary,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              _isIOS ? CupertinoIcons.arrow_up_right_square : Icons.open_in_new,
              size: 16,
              color: AppTheme.accent,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Toast Overlay ────────────────────────────────────────────────────────────

class _ToastOverlay extends StatefulWidget {
  final String message;
  const _ToastOverlay({required this.message});

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _opacity = CurvedAnimation(parent: _ctrl, curve: Curves.easeOut);
    _ctrl.forward();
    Future.delayed(const Duration(milliseconds: 1400), () {
      if (mounted) _ctrl.reverse();
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: MediaQuery.of(context).padding.bottom + 80,
      left: 40,
      right: 40,
      child: FadeTransition(
        opacity: _opacity,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.3),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            widget.message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: context.appTextPrimary,
              decoration: TextDecoration.none,
            ),
          ),
        ),
      ),
    );
  }
}
