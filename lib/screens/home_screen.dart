import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
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
            top: BorderSide(
                color: AppTheme.border.withValues(alpha: 0.5), width: 0.5),
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

// ── Small Profile Avatar ──────────────────────────────────────────────────────

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
      width: 36,
      height: 36,
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
          ? Image.memory(bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _fallback())
          : _fallback(),
    );
  }

  Widget _fallback() => const Center(
    child: Icon(CupertinoIcons.person_fill,
        size: 18, color: AppTheme.textSecondary),
  );
}

// ── Tab Item ──────────────────────────────────────────────────────────────────

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
            Icon(icon,
                size: 22,
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
  List<TimetableEntry> _tomorrow = [];
  bool _loadingTimetable = true;
  String? _errorTimetable;

  List<_RecentGrade> _recentGrades = [];
  bool _loadingGrades = true;

  String? _mensaToday;
  bool _loadingMensa = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loadingTimetable = true;
      _loadingGrades = true;
      _loadingMensa = true;
      _errorTimetable = null;
    });
    await Future.wait([
      _loadTimetable(),
      _loadGrades(),
      _loadMensa(),
    ]);
  }

  // ── Lädt die ganze Woche → filtert heute + morgen ────────────────────────
  Future<void> _loadTimetable() async {
    try {
      final now = DateTime.now();
      // getWeekTimetable() returns all entries for the current week with dates
      final allWeek = await widget.service.getWeekTimetable();

      final todayInt = _dateInt(now);
      final tomorrowInt = _dateInt(now.add(const Duration(days: 1)));

      if (mounted) {
        setState(() {
          _today = allWeek.where((e) => e.date == todayInt).toList();
          _tomorrow = allWeek.where((e) => e.date == tomorrowInt).toList();
          _loadingTimetable = false;
        });
      }
    } on WebUntisException catch (e) {
      if (mounted) {
        setState(() {
          _errorTimetable = e.message;
          _loadingTimetable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorTimetable = '$e';
          _loadingTimetable = false;
        });
      }
    }
  }

  // ── Sammelt ALLE Noten aus allen Fächern, sortiert neueste zuerst ─────────
  // GradeEntry.date ist YYYYMMDD als int — sort descending = neueste zuerst.
  // Der Service sortiert intern aufsteigend; hier drehen wir das um.
  Future<void> _loadGrades() async {
    try {
      final subjects = await widget.service.getAllGrades();
      final allGrades = <_RecentGrade>[];

      for (final subject in subjects) {
        for (final grade in subject.grades) {
          if (grade.markDisplayValue <= 0) continue; // leere Einträge überspringen
          allGrades.add(_RecentGrade(
            subject: subject.subjectName,
            value: grade.markDisplayValue,
            date: grade.date, // YYYYMMDD integer
            type: grade.examType,
          ));
        }
      }

      // Neueste Note zuerst (YYYYMMDD descending)
      allGrades.sort((a, b) => b.date.compareTo(a.date));

      if (mounted) {
        setState(() {
          _recentGrades = allGrades.take(3).toList();
          _loadingGrades = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingGrades = false);
    }
  }

  Future<void> _loadMensa() async {
    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http
          .get(Uri.parse('https://mensa.plattnericus.dev/mensa.json'))
          .timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final dishes = (json['menu']?['dishes'] as List?) ?? [];
        final todayDishes =
        dishes.where((d) => d['date'] == todayStr).toList();

        if (mounted) {
          if (todayDishes.isEmpty) {
            setState(() {
              _mensaToday = null;
              _loadingMensa = false;
            });
          } else {
            final main = todayDishes.firstWhere(
                  (d) => (d['category'] ?? '')
                  .toString()
                  .toLowerCase()
                  .contains('haupt'),
              orElse: () => todayDishes.first,
            );
            final nameMap = main['name'] as Map<String, dynamic>?;
            final name =
                nameMap?['de'] ?? nameMap?.values.first ?? 'Unbekanntes Gericht';
            setState(() {
              _mensaToday = '$name';
              _loadingMensa = false;
            });
          }
        }
      } else {
        if (mounted) setState(() => _loadingMensa = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMensa = false);
    }
  }

  int _dateInt(DateTime d) => int.parse(
      '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}');

  bool _isCurrentLesson(TimetableEntry e, DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    final s = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
    final en = (e.endTime ~/ 100) * 60 + (e.endTime % 100);
    return nowMins >= s && nowMins < en;
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = [
      'Montag', 'Dienstag', 'Mittwoch', 'Donnerstag',
      'Freitag', 'Samstag', 'Sonntag'
    ];
    final months = [
      'Januar', 'Februar', 'März', 'April', 'Mai', 'Juni',
      'Juli', 'August', 'September', 'Oktober', 'November', 'Dezember'
    ];

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

    final todayExams = _today.where((e) => e.isExam).toList();
    final tomorrowExams = _tomorrow.where((e) => e.isExam).toList();
    final hasExam = todayExams.isNotEmpty || tomorrowExams.isNotEmpty;

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
                          fontSize: 14, color: AppTheme.textSecondary),
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

            // ── Prüfungs-Card (immer sichtbar nach dem Laden) ──
            if (!_loadingTimetable && _errorTimetable == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: _ExamCard(
                    todayExams: todayExams,
                    tomorrowExams: tomorrowExams,
                    hasExam: hasExam,
                  ),
                ),
              ),

            // ── Jetzt / Als Nächstes ──
            if (!_loadingTimetable &&
                _errorTimetable == null &&
                _today.isNotEmpty &&
                (currentLesson != null || nextLesson != null))
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

            // ── Stundenplan-Liste (KEIN "Kein Unterricht"-Item mehr) ──
            if (_loadingTimetable)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child:
                  Center(child: CupertinoActivityIndicator(radius: 14)),
                ),
              )
            else if (_errorTimetable != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child:
                  _ErrorCard(message: _errorTimetable!, onRetry: _load),
                ),
              )
            else if (_today.isNotEmpty) ...[
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
                    child: Text(
                      '${_today.length} Stunden heute',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
                          lessonNr: widget.service
                              .getLessonNumber(_today[i].startTime),
                          isNow: _isCurrentLesson(_today[i], now),
                        ),
                      ),
                      childCount: _today.length,
                    ),
                  ),
                ),
              ],

            // ── Mensa + Letzte Noten ──
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: _MensaPreviewCard(
                        dish: _mensaToday,
                        loading: _loadingMensa,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _RecentGradesCard(
                        grades: _recentGrades,
                        loading: _loadingGrades,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

// ── Helper model ──────────────────────────────────────────────────────────────

class _RecentGrade {
  final String subject;
  final double value;
  final int date;
  final String type;
  const _RecentGrade({
    required this.subject,
    required this.value,
    required this.date,
    required this.type,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  PRÜFUNGS-CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _ExamCard extends StatelessWidget {
  final List<TimetableEntry> todayExams;
  final List<TimetableEntry> tomorrowExams;
  final bool hasExam;

  const _ExamCard({
    required this.todayExams,
    required this.tomorrowExams,
    required this.hasExam,
  });

  @override
  Widget build(BuildContext context) {
    // ── Grün: keine Prüfung ──
    if (!hasExam) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: AppTheme.success.withValues(alpha: 0.25), width: 1),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: AppTheme.success.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Icon(CupertinoIcons.checkmark_seal_fill,
                    size: 15, color: AppTheme.success),
              ),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Keine Prüfung demnächst',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.success,
                    ),
                  ),
                  Text(
                    'Heute und morgen ist alles entspannt.',
                    style: TextStyle(
                        fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // ── Gelb: Prüfung vorhanden ──
    final urgentToday = todayExams.isNotEmpty;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.warning.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: AppTheme.warning.withValues(alpha: 0.38), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: AppTheme.warning.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Center(
              child: Icon(CupertinoIcons.exclamationmark_triangle_fill,
                  size: 15, color: AppTheme.warning),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  urgentToday ? '⚠️  Prüfung heute!' : '📅  Prüfung morgen!',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.warning,
                  ),
                ),
                const SizedBox(height: 4),
                if (todayExams.isNotEmpty)
                  _ExamLine(label: 'Heute', exams: todayExams),
                if (tomorrowExams.isNotEmpty)
                  _ExamLine(label: 'Morgen', exams: tomorrowExams),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamLine extends StatelessWidget {
  final String label;
  final List<TimetableEntry> exams;
  const _ExamLine({required this.label, required this.exams});

  @override
  Widget build(BuildContext context) {
    final names = exams.map((e) => e.displayName).join(', ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(
              fontSize: 12, color: AppTheme.textSecondary),
          children: [
            TextSpan(
              text: '$label: ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: names),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MENSA PREVIEW CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _MensaPreviewCard extends StatelessWidget {
  final String? dish;
  final bool loading;
  const _MensaPreviewCard({this.dish, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: const Color(0xFFFF6B35).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(CupertinoIcons.flame_fill,
                      size: 14, color: Color(0xFFFF6B35)),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Mensa',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const CupertinoActivityIndicator(radius: 9)
          else if (dish != null)
            Text(dish!,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis)
          else
            const Text('Heute gibts nichts!',
                style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                    height: 1.3)),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LETZTE NOTEN CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _RecentGradesCard extends StatelessWidget {
  final List<_RecentGrade> grades;
  final bool loading;
  const _RecentGradesCard({required this.grades, required this.loading});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(CupertinoIcons.chart_bar_fill,
                      size: 14, color: AppTheme.accent),
                ),
              ),
              const SizedBox(width: 8),
              const Text('Letzte Noten',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary)),
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const CupertinoActivityIndicator(radius: 9)
          else if (grades.isEmpty)
            const Text('Noch keine Noten',
                style:
                TextStyle(fontSize: 12, color: AppTheme.textSecondary))
          else
            Column(children: grades.map((g) => _GradeRow(grade: g)).toList()),
        ],
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  final _RecentGrade grade;
  const _GradeRow({required this.grade});

  Color _gradeColor(double v) {
    if (v >= 9) return AppTheme.success;
    if (v >= 7) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return const Color(0xFFFF9F0A);
    return AppTheme.danger;
  }

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade.value);
    final d = grade.date.toString();
    // YYYYMMDD → DD.MM
    final dateStr =
    d.length == 8 ? '${d.substring(6)}.${d.substring(4, 6)}' : '';
    final valStr = grade.value % 1 == 0
        ? grade.value.toInt().toString()
        : grade.value.toStringAsFixed(1);

    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Row(
        children: [
          Expanded(
            child: Text(
              grade.subject,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(dateStr,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textTertiary)),
          const SizedBox(width: 5),
          Container(
            width: 32,
            height: 24,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(valStr,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color)),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  NOW / NEXT CARD
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
              ? [
            AppTheme.accent.withValues(alpha: 0.15),
            AppTheme.accent.withValues(alpha: 0.05)
          ]
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
                padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
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
                    color: isCurrent
                        ? AppTheme.accent
                        : AppTheme.textSecondary,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${entry.startFormatted} – ${entry.endFormatted}',
                style: TextStyle(
                  fontSize: 13,
                  color: isCurrent
                      ? AppTheme.accent
                      : AppTheme.textSecondary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 4,
                height: 36,
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
                    if (entry.teacherName.isNotEmpty ||
                        entry.roomName.isNotEmpty)
                      Text(
                        [entry.teacherName, entry.roomName]
                            .where((s) => s.isNotEmpty)
                            .join(' · '),
                        style: const TextStyle(
                            fontSize: 13, color: AppTheme.textSecondary),
                      ),
                  ],
                ),
              ),
              if (nr != null)
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Center(
                    child: Text(nr,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LESSON CARD
// ═══════════════════════════════════════════════════════════════════════════════

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
            ? Border.all(
            color: AppTheme.accent.withValues(alpha: 0.5), width: 1.5)
            : null,
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Column(
              children: [
                if (lessonNr != null)
                  Text(lessonNr!,
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: color.withValues(alpha: 0.8)))
                else
                  Container(
                      width: 4,
                      height: 36,
                      decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(2))),
              ],
            ),
          ),
          const SizedBox(width: 12),
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
                    decoration:
                    entry.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    if (entry.teacherName.isNotEmpty)
                      Text(entry.teacherName,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                    if (entry.teacherName.isNotEmpty &&
                        entry.roomName.isNotEmpty)
                      const Text(' · ',
                          style: TextStyle(
                              fontSize: 13, color: AppTheme.textTertiary)),
                    if (entry.roomName.isNotEmpty)
                      Text(entry.roomName,
                          style: const TextStyle(
                              fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(entry.startFormatted,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: isNow ? AppTheme.accent : AppTheme.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  )),
              Text(entry.endFormatted,
                  style: const TextStyle(
                      fontSize: 13,
                      color: AppTheme.textTertiary,
                      fontFeatures: [FontFeature.tabularFigures()])),
              if (entry.isExam)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.warning.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Prüfung',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.warning)),
                  ),
                ),
              if (entry.isCancelled)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppTheme.danger.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text('Entfällt',
                        style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
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

// ═══════════════════════════════════════════════════════════════════════════════
//  ERROR CARD
// ═══════════════════════════════════════════════════════════════════════════════

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
              style: const TextStyle(
                  color: AppTheme.textSecondary, fontSize: 14)),
          const SizedBox(height: 14),
          CupertinoButton(
            padding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(10),
            minimumSize: Size.zero,
            onPressed: onRetry,
            child: const Text('Erneut versuchen',
                style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );
  }
}