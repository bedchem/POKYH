import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';

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

  // Einstellungen (nur Theme & Sprache)
  String _themeMode = 'system';   // 'light' | 'dark' | 'system'
  String _language = 'de';        // 'de' | 'it' | 'en'

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

  // ──────────────────────────────────────────────────────────────────────────
  // Logout
  // ──────────────────────────────────────────────────────────────────────────
  void _confirmLogout() {
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
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Cache leeren
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('mensa_cache');
      await Future.delayed(const Duration(milliseconds: 400));
      if (!mounted) return;
      _showToast('Cache geleert');
    } catch (_) {
      if (mounted) _showToast('Fehler beim Leeren');
    } finally {
      if (mounted) setState(() => _clearingCache = false);
    }
  }

  void _showToast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        backgroundColor: AppTheme.surface,
      ),
    );
  }

  void _copyUserId() {
    final id = widget.service.studentId?.toString() ?? '';
    if (id.isEmpty) return;
    Clipboard.setData(ClipboardData(text: id));
    _showToast('ID kopiert: $id');
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Feedback per E‑Mail
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'feedback@plattnericus.dev',
      queryParameters: {
        'subject': '[POCKYH] Feedback',
        'body': '\n\n---\nVersion: 1.0.0\nSchule: LBS Brixen',
      },
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    } else {
      _showToast('Mail‑App nicht verfügbar');
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // GitHub öffnen
  // ──────────────────────────────────────────────────────────────────────────
  Future<void> _openGitHub() async {
    final uri = Uri.parse('https://github.com/bedchem/POKYH');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _showToast('Browser nicht verfügbar');
    }
  }

  void _showAbout() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('POCKYH'),
        content: const Text(
          'Version 1.0.0\n\n'
              'Die All‑in‑One Schul‑App für die LBS Brixen.\n\n'
              '© 2025 – MIT Lizenz',
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
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Theme‑Auswahl (CupertinoActionSheet – OS‑Style)
  // ──────────────────────────────────────────────────────────────────────────
  void _showThemePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Erscheinungsbild'),
        actions: [
          _themeAction(ctx, 'light', 'Hell', CupertinoIcons.sun_max),
          _themeAction(ctx, 'system', 'Automatisch (System)', CupertinoIcons.circle_lefthalf_fill),
          _themeAction(ctx, 'dark', 'Dunkel', CupertinoIcons.moon),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _themeAction(
      BuildContext ctx,
      String value,
      String label,
      IconData icon,
      ) {
    return CupertinoActionSheetAction(
      onPressed: () {
        setState(() => _themeMode = value);
        _save('themeMode', value);
        Navigator.pop(ctx);
        // Optional: Theme-Provider hier benachrichtigen
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: _themeMode == value ? AppTheme.accent : AppTheme.textPrimary),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _themeMode == value ? AppTheme.accent : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Sprach‑Auswahl (CupertinoActionSheet – OS‑Style)
  // ──────────────────────────────────────────────────────────────────────────
  void _showLanguagePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sprache (Mensa‑Menü)'),
        actions: [
          _langAction(ctx, 'de', 'Deutsch'),
          _langAction(ctx, 'it', 'Italiano'),
          _langAction(ctx, 'en', 'English'),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
      ),
    );
  }

  CupertinoActionSheetAction _langAction(BuildContext ctx, String code, String label) {
    return CupertinoActionSheetAction(
      onPressed: () {
        setState(() => _language = code);
        _save('language', code);
        Navigator.pop(ctx);
      },
      child: Text(
        label,
        style: TextStyle(
          color: _language == code ? AppTheme.accent : AppTheme.textPrimary,
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Hilfsfunktionen für Anzeigetexte
  // ──────────────────────────────────────────────────────────────────────────
  String _themeLabel() {
    switch (_themeMode) {
      case 'light': return 'Hell';
      case 'dark': return 'Dunkel';
      default: return 'System';
    }
  }

  String _languageLabel() {
    switch (_language) {
      case 'de': return 'Deutsch';
      case 'it': return 'Italiano';
      default: return 'English';
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // Build
  // ──────────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final username = widget.service.username ?? 'Schüler';

    return Scaffold(
      backgroundColor: AppTheme.bg,
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
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          CupertinoIcons.chevron_left,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Profil',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
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
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                              ),
                            ),
                            const SizedBox(height: 3),
                            const _MetaRow(
                              icon: CupertinoIcons.building_2_fill,
                              text: 'LBS Brixen',
                            ),
                            if (widget.service.studentId != null) ...[
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: _copyUserId,
                                child: _MetaRow(
                                  icon: CupertinoIcons.number,
                                  text: 'ID: ${widget.service.studentId}',
                                  hint: 'Tippen zum Kopieren',
                                ),
                              ),
                            ],
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Einstellungen (Theme & Sprache)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: CupertinoIcons.circle_lefthalf_fill,
                      title: 'Erscheinungsbild',
                      subtitle: _themeLabel(),
                      onTap: _showThemePicker,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: CupertinoIcons.globe,
                      title: 'Sprache (Mensa)',
                      subtitle: _languageLabel(),
                      onTap: _showLanguagePicker,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Weitere Aktionen
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  children: [
                    _ActionTile(
                      icon: CupertinoIcons.trash,
                      title: 'Cache leeren',
                      subtitle: 'Gespeicherte Mensa‑Daten entfernen',
                      loading: _clearingCache,
                      onTap: _clearingCache ? null : _clearCache,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: CupertinoIcons.chat_bubble_text,
                      title: 'Feedback senden',
                      subtitle: 'Idee oder Problem melden',
                      onTap: _sendFeedback,
                    ),
                    const SizedBox(height: 12),
                    _ActionTile(
                      icon: CupertinoIcons.info_circle,
                      title: 'Über POCKYH',
                      subtitle: 'Version 1.0.0 · MIT Lizenz',
                      onTap: _showAbout,
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),

            // Abmelden Button
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
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.square_arrow_left, size: 17, color: AppTheme.danger),
                        SizedBox(width: 8),
                        Text(
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
// Hilfs‑Widgets (unverändert, außer notwendiger Anpassungen)
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
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
    child: Text(
      (widget.service.username ?? '?')[0].toUpperCase(),
      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.accent),
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
        Icon(icon, size: 12, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
        if (hint != null) ...[
          const SizedBox(width: 4),
          Icon(CupertinoIcons.doc_on_clipboard, size: 10, color: AppTheme.textTertiary),
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
      decoration: const BoxDecoration(color: AppTheme.success, shape: BoxShape.circle),
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
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.2)),
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
                  ? const CupertinoActivityIndicator()
                  : Icon(icon, size: 18, color: AppTheme.accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500, color: AppTheme.textPrimary)),
                  Text(subtitle, style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right, size: 16, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}