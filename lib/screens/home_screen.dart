import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'timetable_screen.dart';
import 'grades_screen.dart';
import 'mensa_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  final WebUntisService service;
  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      _DashboardTab(service: widget.service),
      TimetableScreen(service: widget.service),
      GradesScreen(service: widget.service),
      const MensaScreen(),
    ];
  }

  Future<void> _logout() async {
    await widget.service.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => const LoginScreen(),
        transitionsBuilder: (_, a, __, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _openProfile() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ProfileScreen(
          service: widget.service,
          onLogout: _logout,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: _screens),
          // ── Persistent profile button (top right) ──
          Positioned(
            top: MediaQuery.of(context).padding.top + 14,
            right: 20,
            child: GestureDetector(
              onTap: _openProfile,
              child: _SmallProfileAvatar(service: widget.service),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(color: AppTheme.border.withValues(alpha: 0.5), width: 0.5),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 6, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TabItem(
                  icon: CupertinoIcons.house_fill,
                  label: 'Home',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _TabItem(
                  icon: CupertinoIcons.calendar,
                  label: 'Stundenplan',
                  active: _tab == 1,
                  onTap: () => setState(() => _tab = 1),
                ),
                _TabItem(
                  icon: CupertinoIcons.chart_bar_fill,
                  label: 'Noten',
                  active: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
                _TabItem(
                  icon: CupertinoIcons.flame_fill,
                  label: 'Mensa',
                  active: _tab == 3,
                  onTap: () => setState(() => _tab = 3),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small Profile Avatar (top right) ─────────────────────────────────────────

class _SmallProfileAvatar extends StatefulWidget {
  final WebUntisService service;
  const _SmallProfileAvatar({required this.service});

  @override
  State<_SmallProfileAvatar> createState() => _SmallProfileAvatarState();
}

class _SmallProfileAvatarState extends State<_SmallProfileAvatar> {
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
      width: 36, height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
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

  Widget _fallback() {
    return const Center(
      child: Icon(CupertinoIcons.person_fill,
          size: 18, color: AppTheme.textSecondary),
    );
  }
}

// ── Tab Item ─────────────────────────────────────────────────────────────────

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 72,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 22,
                color: active ? AppTheme.accent : AppTheme.textTertiary),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? AppTheme.accent : AppTheme.textTertiary,
                )),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatefulWidget {
  final WebUntisService service;
  const _DashboardTab({required this.service});

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab> {
  List<TimetableEntry> _today = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await widget.service.getTimetable();
      if (mounted) setState(() { _today = entries; _loading = false; });
    } on WebUntisException catch (e) {
      if (!mounted) return;
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
    final months = ['Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'];

    // Find current/next lesson
    TimetableEntry? currentLesson;
    TimetableEntry? nextLesson;
    for (final e in _today) {
      if (_isCurrentLesson(e, now)) {
        currentLesson = e;
      } else if (nextLesson == null) {
        final startMins = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
        final nowMins = now.hour * 60 + now.minute;
        if (startMins > nowMins) nextLesson = e;
      }
    }

    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 60, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${weekdays[now.weekday - 1]}, ${now.day}. ${months[now.month - 1]}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Heute',
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 20)),

            // ── Now/Next card ──
            if (!_loading && _error == null && _today.isNotEmpty && (currentLesson != null || nextLesson != null))
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: _NowNextCard(
                    current: currentLesson,
                    next: nextLesson,
                    service: widget.service,
                  ),
                ),
              ),

            // ── Content ──
            if (_loading)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CupertinoActivityIndicator(radius: 14),
                      SizedBox(height: 14),
                      Text('Stundenplan wird geladen\u2026',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
                    ],
                  ),
                ),
              )
            else if (_error != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ErrorCard(message: _error!, onRetry: _load),
                ),
              )
            else if (_today.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _InfoCard(
                    icon: CupertinoIcons.sun_max_fill,
                    title: 'Kein Unterricht',
                    subtitle: 'Heute hast du frei!',
                    color: AppTheme.success,
                  ),
                ),
              )
            else ...[
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Text(
                    '${_today.length} Stunden heute',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary),
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _LessonCard(
                        entry: _today[i],
                        lessonNr: widget.service.getLessonNumber(_today[i].startTime),
                        isNow: _isCurrentLesson(_today[i], now),
                      ),
                    ),
                    childCount: _today.length,
                  ),
                ),
              ),
            ],

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  bool _isCurrentLesson(TimetableEntry e, DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    final startH = e.startTime ~/ 100;
    final startM = e.startTime % 100;
    final endH = e.endTime ~/ 100;
    final endM = e.endTime % 100;
    return nowMins >= (startH * 60 + startM) && nowMins < (endH * 60 + endM);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  WIDGETS
// ═══════════════════════════════════════════════════════════════════════════════

class _NowNextCard extends StatelessWidget {
  final TimetableEntry? current;
  final TimetableEntry? next;
  final WebUntisService service;
  const _NowNextCard({this.current, this.next, required this.service});

  @override
  Widget build(BuildContext context) {
    final entry = current ?? next!;
    final isCurrent = current != null;
    final color = entry.isCancelled
        ? AppTheme.danger
        : AppTheme.colorForSubject(entry.subjectName);
    final nr = service.getLessonNumber(entry.startTime);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isCurrent
              ? [AppTheme.accent.withValues(alpha: 0.15), AppTheme.accent.withValues(alpha: 0.05)]
              : [AppTheme.surface, AppTheme.surface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isCurrent
              ? AppTheme.accent.withValues(alpha: 0.3)
              : AppTheme.border.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: isCurrent
                      ? AppTheme.accent.withValues(alpha: 0.2)
                      : AppTheme.textTertiary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  isCurrent ? 'Jetzt' : 'Als Nächstes',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isCurrent ? AppTheme.accent : AppTheme.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${entry.startFormatted} – ${entry.endFormatted}',
                style: TextStyle(
                  fontSize: 13,
                  color: isCurrent ? AppTheme.accent : AppTheme.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 4, height: 36,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.displayName,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                    if (entry.teacherName.isNotEmpty || entry.roomName.isNotEmpty)
                      Text(
                        [entry.teacherName, entry.roomName]
                            .where((s) => s.isNotEmpty)
                            .join(' \u00b7 '),
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
              if (nr != null)
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(nr,
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LessonCard extends StatelessWidget {
  final TimetableEntry entry;
  final String? lessonNr;
  final bool isNow;

  const _LessonCard({required this.entry, this.lessonNr, this.isNow = false});

  @override
  Widget build(BuildContext context) {
    final color = entry.isCancelled
        ? AppTheme.danger
        : entry.isExam
            ? AppTheme.warning
            : AppTheme.colorForSubject(entry.subjectName);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: isNow
            ? Border.all(color: AppTheme.accent.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          // Lesson number + color bar
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (lessonNr != null)
                  Text(
                    lessonNr!,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: color.withValues(alpha: 0.8),
                    ),
                  )
                else
                  Container(
                    width: 4,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),

          // Subject + Teacher
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.displayName,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: entry.isCancelled
                        ? AppTheme.danger.withValues(alpha: 0.6)
                        : AppTheme.textPrimary,
                    decoration: entry.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (entry.teacherName.isNotEmpty)
                      Text(
                        entry.teacherName,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                    if (entry.teacherName.isNotEmpty && entry.roomName.isNotEmpty)
                      const Text(' \u00b7 ',
                          style: TextStyle(fontSize: 13, color: AppTheme.textTertiary)),
                    if (entry.roomName.isNotEmpty)
                      Text(
                        entry.roomName,
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Time + badges
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                entry.startFormatted,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isNow ? AppTheme.accent : AppTheme.textPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                entry.endFormatted,
                style: const TextStyle(
                  fontSize: 13,
                  color: AppTheme.textTertiary,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              if (entry.isExam)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Prüfung',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: AppTheme.warning)),
                  ),
                ),
              if (entry.isCancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Entfällt',
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600,
                            color: AppTheme.danger)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill,
              color: AppTheme.danger, size: 28),
          const SizedBox(height: 10),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 14),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(10),
            minimumSize: Size.zero,
            onPressed: onRetry,
            child: const Text('Erneut versuchen', style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  const _InfoCard({required this.icon, required this.title, required this.subtitle, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 36),
          const SizedBox(height: 12),
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary)),
          const SizedBox(height: 4),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}
