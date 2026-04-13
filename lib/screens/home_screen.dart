import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:http/http.dart' as http;
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'timetable_screen.dart' show TimetableScreen, TimetableScreenState;
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
  late GlobalKey<TimetableScreenState> _timetableKey;

  @override
  void initState() {
    super.initState();
    _timetableKey = TimetableScreen.createKey();
    _screens = [
      _DashboardTab(
        service: widget.service,
        onMensaTap: () => setState(() => _tab = 3),
        onExamTap: (exam) {
          if (exam == null) return;
          setState(() => _tab = 1);
          // Calculate week offset and day index for the exam
          final now = DateTime.now();
          final examDate = DateTime(
            int.parse(exam.entry.date.toString().substring(0, 4)),
            int.parse(exam.entry.date.toString().substring(4, 6)),
            int.parse(exam.entry.date.toString().substring(6, 8)),
          );
          final thisMonday = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          final weekOffset = examDate.difference(thisMonday).inDays ~/ 7;
          final dayIndex = examDate.weekday - 1;
          // Wait for tab switch, then jump and show detail
          Future.delayed(const Duration(milliseconds: 120), () {
            final timetableState = _timetableKey.currentState;
            if (timetableState != null) {
              timetableState.jumpToWeekAndDay(
                weekOffset: weekOffset,
                dayIndex: dayIndex,
                entry: exam.entry,
                replacement: null,
              );
            }
          });
        },
      ),
      TimetableScreen(service: widget.service, key: _timetableKey),
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
        builder: (_) =>
            ProfileScreen(service: widget.service, onLogout: _logout),
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
              color: AppTheme.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
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
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => const Center(
    child: Icon(
      CupertinoIcons.person_fill,
      size: 18,
      color: AppTheme.textSecondary,
    ),
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
            Icon(
              icon,
              size: 22,
              color: active ? AppTheme.accent : AppTheme.textTertiary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppTheme.accent : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _NextExam {
  final TimetableEntry entry;
  final String label;
  final bool isToday;
  final int daysUntil;
  const _NextExam({
    required this.entry,
    required this.label,
    required this.isToday,
    required this.daysUntil,
  });
}

class _Break {
  final String startTime;
  final String endTime;
  final int durationMins;
  final int minsUntil;
  const _Break({
    required this.startTime,
    required this.endTime,
    required this.durationMins,
    required this.minsUntil,
  });
}

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
//  DASHBOARD TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatefulWidget {
  final WebUntisService service;
  final VoidCallback onMensaTap;
  final void Function(_NextExam?)? onExamTap;
  const _DashboardTab({
    required this.service,
    required this.onMensaTap,
    this.onExamTap,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab>
    with SingleTickerProviderStateMixin {
  List<TimetableEntry> _today = [];
  List<TimetableEntry> _allWeek = [];
  bool _loadingTimetable = true;
  String? _errorTimetable;

  List<_RecentGrade> _recentGrades = [];
  double? _weekAverage;
  bool _loadingGrades = true;

  String? _mensaToday;
  String? _mensaCategory;
  bool _loadingMensa = true;

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _load();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadingTimetable = true;
      _loadingGrades = true;
      _loadingMensa = true;
      _errorTimetable = null;
    });
    _fadeController.reset();
    await Future.wait([_loadTimetable(), _loadGrades(), _loadMensa()]);
    if (mounted) _fadeController.forward();
  }

  Future<void> _loadTimetable() async {
    try {
      final now = DateTime.now();
      final allWeek = await widget.service.getWeekTimetable();
      final todayInt = _dateInt(now);
      if (mounted) {
        setState(() {
          _allWeek = allWeek;
          _today = allWeek.where((e) => e.date == todayInt).toList();
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

  Future<void> _loadGrades() async {
    try {
      final subjects = await widget.service.getAllGrades();
      final allGrades = <_RecentGrade>[];
      double sum = 0;
      int count = 0;
      for (final subject in subjects) {
        for (final grade in subject.grades) {
          if (grade.markDisplayValue <= 0) continue;
          allGrades.add(
            _RecentGrade(
              subject: subject.subjectName,
              value: grade.markDisplayValue,
              date: grade.date,
              type: grade.examType,
            ),
          );
          sum += grade.markDisplayValue;
          count++;
        }
      }
      allGrades.sort((a, b) => b.date.compareTo(a.date));
      if (mounted) {
        setState(() {
          _recentGrades = allGrades.take(3).toList();
          _weekAverage = count > 0 ? sum / count : null;
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

      if (response.statusCode != 200) {
        if (mounted) setState(() => _loadingMensa = false);
        return;
      }

      final json = jsonDecode(response.body);

      List<dynamic> dishes = [];
      if (json is Map) {
        final menu = json['menu'];
        if (menu is Map) {
          dishes = (menu['dishes'] as List?) ?? [];
        } else if (menu is List) {
          dishes = menu;
        } else {
          dishes = (json['dishes'] as List?) ?? [];
        }
      } else if (json is List) {
        dishes = json;
      }

      final todayDishes = dishes.where((d) => d['date'] == todayStr).toList();

      if (!mounted) return;

      if (todayDishes.isEmpty) {
        setState(() {
          _mensaToday = null;
          _loadingMensa = false;
        });
        return;
      }

      final main = todayDishes.firstWhere(
        (d) => (d['category'] ?? '').toString().toLowerCase().contains('haupt'),
        orElse: () => todayDishes.first,
      );

      String name = 'Unbekanntes Gericht';
      final nameField = main['name'];
      if (nameField is Map) {
        name = (nameField['de'] ?? nameField.values.first ?? name).toString();
      } else if (nameField is String) {
        name = nameField;
      }

      String? category;
      final catField = main['category'];
      if (catField is String && catField.isNotEmpty) {
        category = catField;
      }

      setState(() {
        _mensaToday = name;
        _mensaCategory = category;
        _loadingMensa = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMensa = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _dateInt(DateTime d) => int.parse(
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
  );

  bool _isCurrentLesson(TimetableEntry e, DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    final s = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
    final en = (e.endTime ~/ 100) * 60 + (e.endTime % 100);
    return nowMins >= s && nowMins < en;
  }

  TimetableEntry? _getNextLesson(DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    for (final e in _today) {
      final startMins = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
      if (startMins > nowMins) return e;
    }
    return null;
  }

  TimetableEntry? _getCurrentLesson(DateTime now) {
    for (final e in _today) {
      if (_isCurrentLesson(e, now)) return e;
    }
    return null;
  }

  String? _getSchoolEnd() {
    if (_today.isEmpty) return null;
    final last = _today.last;
    final h = last.endTime ~/ 100;
    final m = last.endTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int? _minsUntilEnd(DateTime now) {
    if (_today.isEmpty) return null;
    final last = _today.last;
    final endH = last.endTime ~/ 100;
    final endM = last.endTime % 100;
    final endMins = endH * 60 + endM;
    final nowMins = now.hour * 60 + now.minute;
    if (endMins <= nowMins) return null;
    return endMins - nowMins;
  }

  _Break? _getNextBreak(DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    for (int i = 0; i < _today.length - 1; i++) {
      final curr = _today[i];
      final next = _today[i + 1];
      final currEndMins = (curr.endTime ~/ 100) * 60 + (curr.endTime % 100);
      final nextStartMins =
          (next.startTime ~/ 100) * 60 + (next.startTime % 100);
      final gap = nextStartMins - currEndMins;
      if (gap >= 5 && currEndMins > nowMins) {
        return _Break(
          startTime: curr.endFormatted,
          endTime: next.startFormatted,
          durationMins: gap,
          minsUntil: currEndMins - nowMins,
        );
      }
    }
    return null;
  }

  _NextExam? _getNextExam(DateTime now) {
    final todayInt = _dateInt(now);
    final exams = _allWeek.where((e) => e.isExam && e.date >= todayInt).toList()
      ..sort(
        (a, b) => a.date == b.date
            ? a.startTime.compareTo(b.startTime)
            : a.date.compareTo(b.date),
      );
    if (exams.isEmpty) return null;
    final e = exams.first;
    final d = e.date.toString();
    final examDate = DateTime(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
    );
    final diff = examDate
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    String label;
    if (diff == 0) {
      label = 'Heute';
    } else if (diff == 1) {
      label = 'Morgen';
    } else {
      const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      label = 'in $diff Tagen (${wd[examDate.weekday - 1]})';
    }
    return _NextExam(
      entry: e,
      label: label,
      isToday: diff == 0,
      daysUntil: diff,
    );
  }

  int _lessonsRemaining(DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    return _today.where((e) {
      final startMins = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
      return startMins > nowMins;
    }).length;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final weekdays = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    final months = [
      'Januar',
      'Februar',
      'März',
      'April',
      'Mai',
      'Juni',
      'Juli',
      'August',
      'September',
      'Oktober',
      'November',
      'Dezember',
    ];

    final currentLesson = _loadingTimetable ? null : _getCurrentLesson(now);
    final nextLesson = _loadingTimetable ? null : _getNextLesson(now);
    final schoolEnd = _getSchoolEnd();
    final minsUntilEnd = _minsUntilEnd(now);
    final nextBreak = _getNextBreak(now);
    final nextExam = _loadingTimetable ? null : _getNextExam(now);
    final remaining = _loadingTimetable ? 0 : _lessonsRemaining(now);

    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // ── Header ──────────────────────────────────────────────────────
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
                      'Home',
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
            // ── Wochen-Übersicht (kompakt) ───────────────────────────────────
            if (!_loadingTimetable && _allWeek.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: _WeekOverviewCard(
                    allWeek: _allWeek,
                    now: now,
                    service: widget.service,
                  ),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
            // ── Nächste Prüfung Banner ───────────────────────────────────────
            if (!_loadingTimetable && _errorTimetable == null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: GestureDetector(
                    onTap: () => widget.onExamTap?.call(nextExam),
                    child: _ExamBanner(nextExam: nextExam),
                  ),
                ),
              ),

            // ── Schulende + Noten (side by side) ────────────────────────────
            if (!_loadingTimetable &&
                _errorTimetable == null &&
                _today.isNotEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        Expanded(
                          child: _TimeInfoCard(
                            icon: CupertinoIcons.flag_fill,
                            label: 'Schulende',
                            value: schoolEnd ?? '—',
                            sub: minsUntilEnd != null
                                ? 'noch ${_fmtDuration(minsUntilEnd)}'
                                : 'vorbei',
                            color: minsUntilEnd != null
                                ? AppTheme.accent
                                : AppTheme.textTertiary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _RecentGradesCard(
                            grades: _recentGrades,
                            average: _weekAverage,
                            loading: _loadingGrades,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // ── Loader / Fehler ──────────────────────────────────────────────
            if (_loadingTimetable)
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  child: Center(child: CupertinoActivityIndicator(radius: 14)),
                ),
              )
            else if (_errorTimetable != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: _ErrorCard(message: _errorTimetable!, onRetry: _load),
                ),
              ),

            // ── Mensa Card (clickable, fullwidth) ────────────────────────────
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: GestureDetector(
                  onTap: widget.onMensaTap,
                  child: _MensaPreviewCard(
                    dish: _mensaToday,
                    category: _mensaCategory,
                    loading: _loadingMensa,
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int mins) {
    if (mins < 60) return '${mins}min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }
}
// ═══════════════════════════════════════════════════════════════════════════════
//  WEEK OVERVIEW CARD  –  compact dot-grid showing the week at a glance
// ═══════════════════════════════════════════════════════════════════════════════

class _WeekOverviewCard extends StatelessWidget {
  final List<TimetableEntry> allWeek;
  final DateTime now;
  final WebUntisService service;

  const _WeekOverviewCard({
    required this.allWeek,
    required this.now,
    required this.service,
  });

  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

  int _dateInt(DateTime d) => int.parse(
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
  );

  @override
  Widget build(BuildContext context) {
    final monday = now.subtract(Duration(days: now.weekday - 1));

    return Container(
      padding: const EdgeInsets.all(16),
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
                  color: AppTheme.tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 14,
                    color: AppTheme.tint,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                'Diese Woche',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: List.generate(5, (i) {
              final day = monday.add(Duration(days: i));
              final dateInt = _dateInt(day);
              final dayEntries = allWeek
                  .where((e) => e.date == dateInt)
                  .toList();
              final isToday =
                  day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;
              final isPast = day.isBefore(
                DateTime(now.year, now.month, now.day),
              );
              final hasExam = dayEntries.any((e) => e.isExam);
              final hasCancelled = dayEntries.any((e) => e.isCancelled);
              final count = dayEntries.length;

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? AppTheme.accent
                            : AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppTheme.accent
                            : hasExam
                            ? AppTheme.warning.withValues(alpha: 0.15)
                            : hasCancelled
                            ? AppTheme.danger.withValues(alpha: 0.10)
                            : AppTheme.card,
                        shape: BoxShape.circle,
                        border: hasExam && !isToday
                            ? Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.5),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Center(
                        child: hasExam
                            ? Icon(
                                CupertinoIcons.doc_text_fill,
                                size: 14,
                                color: isToday
                                    ? Colors.white
                                    : AppTheme.warning,
                              )
                            : Text(
                                count > 0 ? '$count' : '–',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? Colors.white
                                      : isPast
                                      ? AppTheme.textTertiary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 5),
                    // Cancellation indicator dots
                    if (hasCancelled && !hasExam)
                      Container(
                        width: 5,
                        height: 5,
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 5),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 12),
          // Legend
          Row(
            children: [
              _WeekLegendDot(color: AppTheme.warning, label: 'Prüfung'),
              const SizedBox(width: 14),
              _WeekLegendDot(color: AppTheme.danger, label: 'Entfall'),
              const Spacer(),
              Text(
                '${allWeek.length} Std. diese Woche',
                style: const TextStyle(
                  fontSize: 11,
                  color: AppTheme.textTertiary,
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
//  EXAM BANNER  –  shows the next upcoming exam, not just today
// ═══════════════════════════════════════════════════════════════════════════════

class _ExamBanner extends StatelessWidget {
  final _NextExam? nextExam;
  const _ExamBanner({required this.nextExam});

  @override
  Widget build(BuildContext context) {
    if (nextExam == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 14,
              color: AppTheme.success,
            ),
            const SizedBox(width: 8),
            const Text(
              'Keine Prüfung diese Woche',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ],
        ),
      );
    }

    final exam = nextExam!;
    final color = exam.isToday ? AppTheme.danger : AppTheme.warning;
    final icon = exam.isToday
        ? CupertinoIcons.exclamationmark_circle_fill
        : CupertinoIcons.calendar_badge_plus;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              overflow: TextOverflow.ellipsis,
              text: TextSpan(
                children: [
                  TextSpan(
                    text: exam.isToday
                        ? 'Prüfung heute: '
                        : 'Nächste Prüfung: ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.75),
                    ),
                  ),
                  TextSpan(
                    text: exam.entry.displayName,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                  TextSpan(
                    text: '  ${exam.label}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.65),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TIME INFO CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _TimeInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _TimeInfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

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
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Center(child: Icon(icon, size: 13, color: color)),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MENSA PREVIEW CARD  –  rich, food-themed, beautiful
// ═══════════════════════════════════════════════════════════════════════════════

class _MensaPreviewCard extends StatelessWidget {
  final String? dish;
  final String? category;
  final bool loading;
  const _MensaPreviewCard({this.dish, this.category, required this.loading});

  static const _kOrange = Color(0xFFFF6B35);
  static const _kAmber = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kOrange.withValues(alpha: 0.18),
            _kAmber.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: _kOrange.withValues(alpha: 0.25), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: _kOrange.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Center(
                        child: Icon(
                          CupertinoIcons.flame_fill,
                          size: 14,
                          color: _kOrange,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Mensa',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (loading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: CupertinoActivityIndicator(radius: 9),
                  )
                else if (dish != null) ...[
                  const SizedBox(height: 7),
                  // Dish name
                  Text(
                    dish!,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      height: 1.3,
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),
                  // "Mehr" hint
                  Row(
                    children: [
                      const Text(
                        'Zum Menü',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: _kOrange,
                        ),
                      ),
                      const SizedBox(width: 3),
                      Icon(
                        CupertinoIcons.arrow_right,
                        size: 10,
                        color: _kOrange.withValues(alpha: 0.8),
                      ),
                    ],
                  ),
                ] else
                  Text(
                    'Heute nichts\nverfügbar',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RECENT GRADES CARD  –  with overall average indicator
// ═══════════════════════════════════════════════════════════════════════════════

class _RecentGradesCard extends StatelessWidget {
  final List<_RecentGrade> grades;
  final double? average;
  final bool loading;
  const _RecentGradesCard({
    required this.grades,
    required this.loading,
    this.average,
  });

  Color _avgColor(double v) {
    if (v >= 9) return AppTheme.success;
    if (v >= 6.5) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return const Color(0xFFFF9F0A);
    return AppTheme.danger;
  }

  String _fmtAvg(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(1);
  }

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
                  child: Icon(
                    CupertinoIcons.chart_bar_fill,
                    size: 14,
                    color: AppTheme.accent,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Letzte Noten',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              // Average badge
            ],
          ),
          const SizedBox(height: 10),
          if (loading)
            const CupertinoActivityIndicator(radius: 9)
          else if (grades.isEmpty)
            const Text(
              'Noch keine Noten',
              style: TextStyle(fontSize: 12, color: AppTheme.textSecondary),
            )
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

  String _fmtValue(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade.value);
    final d = grade.date.toString();
    final dateStr = d.length == 8
        ? '${d.substring(6)}.${d.substring(4, 6)}'
        : '';
    final valStr = _fmtValue(grade.value);

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
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            dateStr,
            style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary),
          ),
          const SizedBox(width: 5),
          Container(
            constraints: const BoxConstraints(minWidth: 32),
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 6),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Center(
              child: Text(
                valStr,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _WeekLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary),
        ),
      ],
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
                  AppTheme.accent.withValues(alpha: 0.05),
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
                        [
                          entry.teacherName,
                          entry.roomName,
                        ].where((s) => s.isNotEmpty).join(' · '),
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
                        ),
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
                    child: Text(
                      nr,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: color,
                      ),
                    ),
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
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: AppTheme.danger,
            size: 28,
          ),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppTheme.textSecondary, fontSize: 14),
          ),
          const SizedBox(height: 14),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(10),
            minimumSize: Size.zero,
            onPressed: onRetry,
            child: const Text(
              'Erneut versuchen',
              style: TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
