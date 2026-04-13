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
  // ── Settings State ────────────────────────────────────────────────────────
  bool _compactTimetable = false;
  bool _showCancelledLessons = true;
  bool _highlightFreePeriods = true;
  bool _subjectColors = true;
  bool _autoRefresh = true;
  bool _notifyChanges = false;
  bool _notifyMorning = false;
  String _reminderTime = '07:30';
  String _language = 'de';
  String _themeMode = 'system'; // 'light' | 'dark' | 'system'

  // ── Cache State ───────────────────────────────────────────────────────────
  bool _clearingCache = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  // ── Persistence ───────────────────────────────────────────────────────────

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _compactTimetable = prefs.getBool('compactTimetable') ?? false;
      _showCancelledLessons = prefs.getBool('showCancelledLessons') ?? true;
      _highlightFreePeriods = prefs.getBool('highlightFreePeriods') ?? true;
      _subjectColors = prefs.getBool('subjectColors') ?? true;
      _autoRefresh = prefs.getBool('autoRefresh') ?? true;
      _notifyChanges = prefs.getBool('notifyChanges') ?? false;
      _notifyMorning = prefs.getBool('notifyMorning') ?? false;
      _reminderTime = prefs.getString('reminderTime') ?? '07:30';
      _language = prefs.getString('language') ?? 'de';
      _themeMode = prefs.getString('themeMode') ?? 'system';
    });
  }

  Future<void> _save(String key, dynamic value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value is bool) await prefs.setBool(key, value);
    if (value is String) await prefs.setString(key, value);
  }

  // ── Actions ───────────────────────────────────────────────────────────────

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

  Future<void> _clearCache() async {
    setState(() => _clearingCache = true);
    try {
      // Hinweis: Falls WebUntisService eine clearCache()-Methode besitzt,
      // kann diese hier aufgerufen werden. Andernfalls nur SharedPreferences leeren.
      // await widget.service.clearCache();

      // Mensa-Cache aus SharedPreferences entfernen
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('mensa_cache');
      await Future.delayed(const Duration(milliseconds: 600)); // UX pause
      if (!mounted) return;
      _showToast('Cache geleert ✓');
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

  Future<void> _sendFeedback() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'feedback@plattnericus.dev',
      queryParameters: {
        'subject': '[POCKYH] Feedback',
        'body': '\n\n---\nVersion: 1.0.0\nSchule: LBS Brixen',
      },
    );
    // Verwende canLaunch / launch für Kompatibilität mit älteren url_launcher Versionen
    if (await canLaunch(uri.toString())) {
      await launch(uri.toString());
    } else {
      _showToast('Mail-App nicht verfügbar');
    }
  }

  void _showThemePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Design'),
        actions: [
          _themeAction(ctx, 'light', 'Hell', CupertinoIcons.sun_max),
          _themeAction(
            ctx,
            'system',
            'Automatisch (System)',
            CupertinoIcons.circle_lefthalf_fill,
          ),
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
        // TODO: notify ThemeProvider/Riverpod here
      },
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 18,
            color: _themeMode == value ? AppTheme.accent : AppTheme.textPrimary,
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              color: _themeMode == value
                  ? AppTheme.accent
                  : AppTheme.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showLanguagePicker() {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Sprache (Mensa-Menü)'),
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

  CupertinoActionSheetAction _langAction(
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
          color: _language == code ? AppTheme.accent : AppTheme.textPrimary,
        ),
      ),
    );
  }

  void _showReminderTimePicker() {
    final parts = _reminderTime.split(':');
    int hour = int.tryParse(parts[0]) ?? 7;
    int minute = int.tryParse(parts[1]) ?? 30;

    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => Container(
        height: 300,
        color: AppTheme.surface,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Abbrechen'),
                  ),
                  const Text(
                    'Erinnerungszeit',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  CupertinoButton(
                    padding: EdgeInsets.zero,
                    onPressed: () {
                      final time =
                          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
                      setState(() {
                        _reminderTime = time;
                        _notifyMorning = true;
                      });
                      _save('reminderTime', time);
                      _save('notifyMorning', true);
                      Navigator.pop(ctx);
                    },
                    child: Text(
                      'OK',
                      style: TextStyle(
                        color: AppTheme.accent,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: DateTime(2000, 1, 1, hour, minute),
                onDateTimeChanged: (dt) {
                  hour = dt.hour;
                  minute = dt.minute;
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showAbout() {
    showCupertinoDialog(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('POCKYH'),
        content: const Text(
          'Version 1.0.0\n\nDie All-in-One Schul-App für die LBS Brixen.\n\n'
          'Stundenplan, Noten, Mensa & mehr.\n\n'
          '© 2025 – MIT Lizenz',
        ),
        actions: [
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final username = widget.service.username ?? 'Schüler';

    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // ── Header ────────────────────────────────────────────────────
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
                      'Profil & Einstellungen',
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

            // ── Profile Card ───────────────────────────────────────────────
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
                            _MetaRow(
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                      color: AppTheme.success,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 5),
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

            // ── Design ────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Section(
                title: 'Design',
                icon: CupertinoIcons.paintbrush,
                children: [
                  _TapRow(
                    title: 'Erscheinungsbild',
                    subtitle: _themeModeLabel(_themeMode),
                    icon: CupertinoIcons.circle_lefthalf_fill,
                    onTap: _showThemePicker,
                  ),
                ],
              ),
            ),

            // ── Stundenplan ───────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Section(
                title: 'Stundenplan',
                icon: CupertinoIcons.calendar,
                children: [
                  _ToggleRow(
                    title: 'Kompakte Ansicht',
                    subtitle: 'Kleinere Karten für mehr Übersicht',
                    icon: CupertinoIcons.rectangle_compress_vertical,
                    value: _compactTimetable,
                    onChanged: (v) {
                      setState(() => _compactTimetable = v);
                      _save('compactTimetable', v);
                    },
                  ),
                  _ToggleRow(
                    title: 'Entfallene Stunden',
                    subtitle: 'Abgesagte Stunden anzeigen',
                    icon: CupertinoIcons.xmark_circle,
                    value: _showCancelledLessons,
                    onChanged: (v) {
                      setState(() => _showCancelledLessons = v);
                      _save('showCancelledLessons', v);
                    },
                  ),
                  _ToggleRow(
                    title: 'Freistunden hervorheben',
                    subtitle: 'Lücken im Plan farbig markieren',
                    icon: CupertinoIcons.waveform_path,
                    value: _highlightFreePeriods,
                    onChanged: (v) {
                      setState(() => _highlightFreePeriods = v);
                      _save('highlightFreePeriods', v);
                    },
                  ),
                  _ToggleRow(
                    title: 'Fachfarben',
                    subtitle: 'Fächer farblich unterscheiden',
                    icon: CupertinoIcons.color_filter,
                    value: _subjectColors,
                    onChanged: (v) {
                      setState(() => _subjectColors = v);
                      _save('subjectColors', v);
                    },
                  ),
                ],
              ),
            ),

            // ── Benachrichtigungen ─────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Section(
                title: 'Benachrichtigungen',
                icon: CupertinoIcons.bell,
                badge: 'NEU',
                children: [
                  _ToggleRow(
                    title: 'Stundenplanänderungen',
                    subtitle: 'Push bei Vertretung oder Ausfall',
                    icon: CupertinoIcons.bell_fill,
                    value: _notifyChanges,
                    onChanged: (v) {
                      setState(() => _notifyChanges = v);
                      _save('notifyChanges', v);
                      if (v) _showToast('Benachrichtigungen aktiviert');
                    },
                  ),
                  _TapRow(
                    title: 'Morgen-Erinnerung',
                    subtitle: _notifyMorning
                        ? 'Täglich um $_reminderTime Uhr'
                        : 'Ausgeschaltet',
                    icon: CupertinoIcons.clock,
                    trailing: _notifyMorning
                        ? Text(
                            _reminderTime,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.accent,
                              fontWeight: FontWeight.w500,
                            ),
                          )
                        : null,
                    onTap: _showReminderTimePicker,
                  ),
                ],
              ),
            ),

            // ── Allgemein ─────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Section(
                title: 'Allgemein',
                icon: CupertinoIcons.gear,
                children: [
                  _ToggleRow(
                    title: 'Auto-Aktualisierung',
                    subtitle: 'Daten beim Öffnen automatisch laden',
                    icon: CupertinoIcons.arrow_2_circlepath,
                    value: _autoRefresh,
                    onChanged: (v) {
                      setState(() => _autoRefresh = v);
                      _save('autoRefresh', v);
                    },
                  ),
                  _TapRow(
                    title: 'Sprache (Mensa)',
                    subtitle: _languageLabel(_language),
                    icon: CupertinoIcons.globe,
                    onTap: _showLanguagePicker,
                  ),
                  _TapRow(
                    title: 'Feedback senden',
                    subtitle: 'Bug melden oder Idee teilen',
                    icon: CupertinoIcons.chat_bubble_text,
                    onTap: _sendFeedback,
                  ),
                ],
              ),
            ),

            // ── Info ───────────────────────────────────────────────────────
            SliverToBoxAdapter(
              child: _Section(
                title: 'Info',
                icon: CupertinoIcons.info_circle,
                children: [
                  _TapRow(
                    title: 'App-Version',
                    subtitle: 'POCKYH für LBS Brixen',
                    icon: CupertinoIcons.app,
                    trailing: const Text(
                      '1.0.0',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textTertiary,
                      ),
                    ),
                    onTap: _showAbout,
                  ),
                  _TapRow(
                    title: 'Über POCKYH',
                    subtitle: 'Lizenz, Danksagungen',
                    icon: CupertinoIcons.heart,
                    onTap: _showAbout,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 8)),

            // ── Cache & Daten ─────────────────────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _ActionButton(
                        label: _clearingCache
                            ? 'Wird geleert…'
                            : 'Cache leeren',
                        icon: CupertinoIcons.trash,
                        loading: _clearingCache,
                        onTap: _clearingCache ? null : _clearCache,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _ActionButton(
                        label: 'Schule kopieren',
                        icon: CupertinoIcons.doc_on_clipboard,
                        onTap: () {
                          Clipboard.setData(
                            const ClipboardData(text: 'lbs-brixen'),
                          );
                          _showToast('lbs-brixen kopiert');
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

            // ── Logout ────────────────────────────────────────────────────
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
                        Icon(
                          CupertinoIcons.square_arrow_left,
                          size: 17,
                          color: AppTheme.danger,
                        ),
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

  // ── Helpers ───────────────────────────────────────────────────────────────

  String _languageLabel(String code) {
    switch (code) {
      case 'de':
        return 'Deutsch';
      case 'it':
        return 'Italiano';
      case 'en':
        return 'English';
      default:
        return code;
    }
  }

  String _themeModeLabel(String mode) {
    switch (mode) {
      case 'light':
        return 'Hell';
      case 'dark':
        return 'Dunkel';
      default:
        return 'Automatisch (System)';
    }
  }
}

// ── Profile Avatar ────────────────────────────────────────────────────────────

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
              errorBuilder: (_, __, ___) => _fallback(),
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

// ── Meta Row ──────────────────────────────────────────────────────────────────

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
          color: AppTheme.textTertiary.withValues(alpha: 0.7),
        ),
        const SizedBox(width: 5),
        Text(
          text,
          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
        ),
        if (hint != null) ...[
          const SizedBox(width: 4),
          Icon(
            CupertinoIcons.doc_on_clipboard,
            size: 10,
            color: AppTheme.textTertiary,
          ),
        ],
      ],
    );
  }
}

// ── Settings Section ──────────────────────────────────────────────────────────

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final String? badge;
  final List<Widget> children;

  const _Section({
    required this.title,
    required this.icon,
    required this.children,
    this.badge,
  });

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
                Icon(icon, size: 13, color: AppTheme.textTertiary),
                const SizedBox(width: 6),
                Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textTertiary,
                    letterSpacing: 0.8,
                  ),
                ),
                if (badge != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      badge!,
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.warning,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ],
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

// ── Toggle Row ────────────────────────────────────────────────────────────────

class _ToggleRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ToggleRow({
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
          _IconBox(icon: icon),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    color: AppTheme.textPrimary,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
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

// ── Tap Row ───────────────────────────────────────────────────────────────────

class _TapRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;
  final VoidCallback onTap;

  const _TapRow({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.trailing,
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
            _IconBox(icon: icon),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 15,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[trailing!, const SizedBox(width: 6)],
            const Icon(
              CupertinoIcons.chevron_right,
              size: 14,
              color: AppTheme.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}

// ── Icon Box ──────────────────────────────────────────────────────────────────

class _IconBox extends StatelessWidget {
  final IconData icon;
  const _IconBox({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Icon(icon, size: 16, color: AppTheme.accent),
    );
  }
}

// ── Action Button ─────────────────────────────────────────────────────────────

class _ActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool loading;

  const _ActionButton({
    required this.label,
    required this.icon,
    this.onTap,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppTheme.border.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (loading)
              const CupertinoActivityIndicator(radius: 7)
            else
              Icon(icon, size: 15, color: AppTheme.textSecondary),
            const SizedBox(width: 7),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppTheme.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
