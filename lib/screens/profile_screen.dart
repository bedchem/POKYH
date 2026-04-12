import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';

class ProfileScreen extends StatefulWidget {
  final WebUntisService service;
  final VoidCallback onLogout;
  const ProfileScreen({super.key, required this.service, required this.onLogout});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _compactTimetable = false;
  bool _showCancelledLessons = true;
  bool _autoRefresh = true;
  String _language = 'de';

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _compactTimetable = prefs.getBool('compactTimetable') ?? false;
      _showCancelledLessons = prefs.getBool('showCancelledLessons') ?? true;
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _language = prefs.getString('language') ?? 'de';
    });
  }

  Future<void> _setSetting(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) {
      await prefs.setBool(key, value);
    } else if (value is String) {
      await prefs.setString(key, value);
    }
  }

  void _confirmLogout() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Abmelden'),
        content: const Text('Möchtest du dich wirklich abmelden?'),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            child: const Text('Abbrechen'),
            onPressed: () => Navigator.pop(ctx),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            child: const Text('Abmelden'),
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.pop(context);
              widget.onLogout();
            },
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final username = widget.service.username ?? 'Schüler';
    final school = 'LBS Brixen';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: AppTheme.surface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(CupertinoIcons.chevron_left,
                            size: 16, color: AppTheme.textSecondary),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text('Profil & Einstellungen',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary)),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Profile Card ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  padding: const EdgeInsets.all(20),
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
                    border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      // Profile picture
                      _ProfileAvatar(service: widget.service),
                      const SizedBox(width: 16),
                      // Info
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
                            Row(
                              children: [
                                Icon(CupertinoIcons.building_2_fill,
                                    size: 12, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
                                const SizedBox(width: 5),
                                Text(school,
                                    style: const TextStyle(fontSize: 14,
                                        color: AppTheme.textSecondary)),
                              ],
                            ),
                            if (widget.service.studentId != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                children: [
                                  Icon(CupertinoIcons.number,
                                      size: 12, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
                                  const SizedBox(width: 5),
                                  Text('ID: ${widget.service.studentId}',
                                      style: const TextStyle(fontSize: 12,
                                          color: AppTheme.textTertiary)),
                                ],
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 28)),

            // ── Stundenplan Settings ──
            SliverToBoxAdapter(
              child: _SettingsSection(
                title: 'Stundenplan',
                icon: CupertinoIcons.calendar,
                children: [
                  _SettingsToggle(
                    title: 'Kompakte Ansicht',
                    subtitle: 'Kleinere Karten für mehr Übersicht',
                    icon: CupertinoIcons.rectangle_compress_vertical,
                    value: _compactTimetable,
                    onChanged: (v) {
                      setState(() => _compactTimetable = v);
                      _setSetting('compactTimetable', v);
                    },
                  ),
                  _SettingsToggle(
                    title: 'Entfallene Stunden',
                    subtitle: 'Abgesagte Stunden anzeigen',
                    icon: CupertinoIcons.xmark_circle,
                    value: _showCancelledLessons,
                    onChanged: (v) {
                      setState(() => _showCancelledLessons = v);
                      _setSetting('showCancelledLessons', v);
                    },
                  ),
                ],
              ),
            ),

            // ── Allgemein Settings ──
            SliverToBoxAdapter(
              child: _SettingsSection(
                title: 'Allgemein',
                icon: CupertinoIcons.gear,
                children: [
                  _SettingsToggle(
                    title: 'Auto-Aktualisierung',
                    subtitle: 'Daten beim Öffnen automatisch laden',
                    icon: CupertinoIcons.arrow_2_circlepath,
                    value: _autoRefresh,
                    onChanged: (v) {
                      setState(() => _autoRefresh = v);
                      _setSetting('autoRefresh', v);
                    },
                  ),
                  _SettingsTap(
                    title: 'Sprache (Mensa)',
                    subtitle: _languageLabel(_language),
                    icon: CupertinoIcons.globe,
                    onTap: () => _showLanguagePicker(),
                  ),
                ],
              ),
            ),

            // ── Info Section ──
            SliverToBoxAdapter(
              child: _SettingsSection(
                title: 'Info',
                icon: CupertinoIcons.info_circle,
                children: [
                  _SettingsTap(
                    title: 'App-Version',
                    subtitle: '1.0.0',
                    icon: CupertinoIcons.app,
                    onTap: () {},
                  ),
                  _SettingsTap(
                    title: 'Schule',
                    subtitle: 'LBS Brixen (lbs-brixen)',
                    icon: CupertinoIcons.building_2_fill,
                    onTap: () {},
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Logout Button ──
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
                      border: Border.all(color: AppTheme.danger.withValues(alpha: 0.15)),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(CupertinoIcons.square_arrow_left,
                            size: 17, color: AppTheme.danger),
                        SizedBox(width: 8),
                        Text('Abmelden',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600,
                                color: AppTheme.danger)),
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

  String _languageLabel(String code) {
    switch (code) {
      case 'de': return 'Deutsch';
      case 'it': return 'Italiano';
      case 'en': return 'English';
      default: return code;
    }
  }

  void _showLanguagePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sprache für Mensa-Menü'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () { _setLanguage('de'); Navigator.pop(ctx); },
            child: Text('Deutsch',
                style: TextStyle(
                    color: _language == 'de' ? AppTheme.accent : AppTheme.textPrimary)),
          ),
          CupertinoActionSheetAction(
            onPressed: () { _setLanguage('it'); Navigator.pop(ctx); },
            child: Text('Italiano',
                style: TextStyle(
                    color: _language == 'it' ? AppTheme.accent : AppTheme.textPrimary)),
          ),
          CupertinoActionSheetAction(
            onPressed: () { _setLanguage('en'); Navigator.pop(ctx); },
            child: Text('English',
                style: TextStyle(
                    color: _language == 'en' ? AppTheme.accent : AppTheme.textPrimary)),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          isDefaultAction: true,
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Abbrechen'),
        ),
      ),
    );
  }

  void _setLanguage(String code) {
    setState(() => _language = code);
    _setSetting('language', code);
  }
}

// ── Profile Avatar ───────────────────────────────────────────────────────────

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
      width: 64, height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.accent.withValues(alpha: 0.15),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.3), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallbackIcon(),
            )
          : _fallbackIcon(),
    );
  }

  Widget _fallbackIcon() {
    return Center(
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
}

// ── Settings Section ─────────────────────────────────────────────────────────

class _SettingsSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;
  const _SettingsSection({required this.title, required this.icon, required this.children});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Row(
              children: [
                Icon(icon, size: 14, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(title.toUpperCase(),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: AppTheme.textTertiary, letterSpacing: 0.8)),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (int i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1)
                    Padding(
                      padding: const EdgeInsets.only(left: 52),
                      child: Container(
                        height: 0.5,
                        color: AppTheme.border.withValues(alpha: 0.3),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsToggle extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _SettingsToggle({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(
              color: AppTheme.accent.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(icon, size: 16, color: AppTheme.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
                Text(subtitle,
                    style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
              ],
            ),
          ),
          CupertinoSwitch(
            value: value,
            activeTrackColor: AppTheme.accent,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _SettingsTap extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  const _SettingsTap({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(
          children: [
            Container(
              width: 30, height: 30,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(7),
              ),
              child: Icon(icon, size: 16, color: AppTheme.accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(fontSize: 15, color: AppTheme.textPrimary)),
                  Text(subtitle,
                      style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
                ],
              ),
            ),
            const Icon(CupertinoIcons.chevron_right,
                size: 14, color: AppTheme.textTertiary),
          ],
        ),
      ),
    );
  }
}
