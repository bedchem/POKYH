import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

class TimetableScreen extends StatefulWidget {
  final WebUntisService service;
  const TimetableScreen({super.key, required this.service});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  List<TimetableEntry> _entries = [];
  bool _loading = true;
  String? _error;
  late DateTime _weekStart;
  int _selectedDay = -1;
  late final PageController _pageController;

  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  static const _months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedDay = (now.weekday <= 5) ? now.weekday - 1 : 0;
    _pageController = PageController(initialPage: _selectedDay);
    _load();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final entries = await widget.service.getWeekTimetable(weekStart: _weekStart);
      if (mounted) setState(() { _entries = entries; _loading = false; });
    } on WebUntisException catch (e) {
      if (!mounted) return;
      if (e.isAuthError) {
        Navigator.pushReplacement(context,
            MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = '$e'; _loading = false; });
    }
  }

  void _prevWeek() {
    _weekStart = _weekStart.subtract(const Duration(days: 7));
    _load();
  }

  void _nextWeek() {
    _weekStart = _weekStart.add(const Duration(days: 7));
    _load();
  }

  void _goToToday() {
    final now = DateTime.now();
    _weekStart = now.subtract(Duration(days: now.weekday - 1));
    _selectedDay = (now.weekday <= 5) ? now.weekday - 1 : 0;
    _pageController.jumpToPage(_selectedDay);
    _load();
  }

  List<TimetableEntry> _forDay(int dayIndex) {
    final date = _weekStart.add(Duration(days: dayIndex));
    final dateInt = int.parse(
        '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}');
    return _entries.where((e) => e.date == dateInt).toList();
  }

  bool _isToday(int dayIndex) {
    final date = _weekStart.add(Duration(days: dayIndex));
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool _isThisWeek() {
    final now = DateTime.now();
    final thisMonday = now.subtract(Duration(days: now.weekday - 1));
    return _weekStart.year == thisMonday.year &&
        _weekStart.month == thisMonday.month &&
        _weekStart.day == thisMonday.day;
  }

  int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(startOfYear).inDays;
    return ((diff + startOfYear.weekday) / 7).ceil();
  }

  @override
  Widget build(BuildContext context) {
    final weekEnd = _weekStart.add(const Duration(days: 4));

    return SafeArea(
      child: Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text('Stundenplan',
                          style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary, letterSpacing: -0.5)),
                    ),
                    if (!_isThisWeek())
                      GestureDetector(
                        onTap: _goToToday,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: AppTheme.accent.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text('Heute',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                  color: AppTheme.accent)),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                // Week nav row
                Row(
                  children: [
                    _WeekNavButton(
                      icon: CupertinoIcons.chevron_left,
                      onTap: _prevWeek,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        '${_weekStart.day}. ${_months[_weekStart.month - 1]} – ${weekEnd.day}. ${_months[weekEnd.month - 1]} ${weekEnd.year}',
                        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500,
                            color: AppTheme.textSecondary),
                      ),
                    ),
                    Text(
                      'KW ${_weekNumber(_weekStart)}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                          color: AppTheme.textTertiary),
                    ),
                    const SizedBox(width: 12),
                    _WeekNavButton(
                      icon: CupertinoIcons.chevron_right,
                      onTap: _nextWeek,
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          // ── Day selector (WebUntis-style tabs) ──
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                color: AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: List.generate(5, (i) {
                  final date = _weekStart.add(Duration(days: i));
                  final isSelected = _selectedDay == i;
                  final isToday = _isToday(i);
                  final hasEntries = !_loading && _forDay(i).isNotEmpty;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () {
                        setState(() => _selectedDay = i);
                        _pageController.animateToPage(i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut);
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? AppTheme.accent
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(11),
                        ),
                        child: Column(
                          children: [
                            Text(
                              _dayLabels[i],
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSelected
                                    ? Colors.white.withValues(alpha: 0.7)
                                    : AppTheme.textTertiary,
                              ),
                            ),
                            const SizedBox(height: 1),
                            Container(
                              width: 32, height: 32,
                              decoration: isToday && !isSelected
                                  ? BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: AppTheme.accent, width: 2),
                                    )
                                  : null,
                              child: Center(
                                child: Text(
                                  '${date.day}',
                                  style: TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w700,
                                    color: isSelected
                                        ? Colors.white
                                        : isToday
                                            ? AppTheme.accent
                                            : AppTheme.textPrimary,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 2),
                            AnimatedOpacity(
                              opacity: hasEntries ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 200),
                              child: Container(
                                width: 5, height: 5,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: isSelected
                                      ? Colors.white.withValues(alpha: 0.7)
                                      : AppTheme.accent.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),

          const SizedBox(height: 6),

          // ── Content ──
          if (_loading)
            const Expanded(
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
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(CupertinoIcons.exclamationmark_triangle_fill,
                          color: AppTheme.danger, size: 28),
                      const SizedBox(height: 10),
                      Text(_error!, style: const TextStyle(color: AppTheme.textSecondary)),
                      const SizedBox(height: 14),
                      CupertinoButton(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        minimumSize: Size.zero,
                        onPressed: _load,
                        child: const Text('Erneut versuchen', style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: 5,
                onPageChanged: (i) => setState(() => _selectedDay = i),
                itemBuilder: (_, i) => RefreshIndicator(
                  color: AppTheme.accent,
                  backgroundColor: AppTheme.surface,
                  onRefresh: _load,
                  child: _buildDayView(i),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildDayView(int dayIndex) {
    final dayEntries = _forDay(dayIndex);
    final now = DateTime.now();
    final isToday = _isToday(dayIndex);

    if (dayEntries.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 80),
          Center(
            child: Column(
              children: [
                Container(
                  width: 64, height: 64,
                  decoration: BoxDecoration(
                    color: AppTheme.success.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(CupertinoIcons.sun_max_fill,
                      color: AppTheme.success.withValues(alpha: 0.7), size: 30),
                ),
                const SizedBox(height: 16),
                const Text('Kein Unterricht',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 4),
                Text(
                  isToday ? 'Genieße deinen freien Tag!' : 'An diesem Tag ist nichts eingetragen.',
                  style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    // Build WebUntis-style grid
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      itemCount: dayEntries.length,
      itemBuilder: (_, i) {
        final e = dayEntries[i];
        final nr = widget.service.getLessonNumber(e.startTime);
        final isNow = isToday && _isCurrentLesson(e, now);
        final color = e.isCancelled
            ? AppTheme.danger
            : e.isExam
                ? AppTheme.warning
                : AppTheme.colorForSubject(e.subjectName);

        // Check for gap before this entry
        Widget? gapWidget;
        if (i > 0) {
          final prevEnd = dayEntries[i - 1].endTime;
          if (e.startTime > prevEnd) {
            final gapMins = _timeDiffMinutes(prevEnd, e.startTime);
            if (gapMins >= 10) {
              gapWidget = Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Row(
                        children: [
                          Expanded(child: Container(height: 0.5, color: AppTheme.border.withValues(alpha: 0.3))),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text('$gapMins min Pause',
                                style: const TextStyle(fontSize: 11, color: AppTheme.textTertiary)),
                          ),
                          Expanded(child: Container(height: 0.5, color: AppTheme.border.withValues(alpha: 0.3))),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }
          }
        }

        return Column(
          children: [
            if (gapWidget != null) gapWidget,
            _LessonTile(
              entry: e,
              lessonNr: nr,
              isNow: isNow,
              color: color,
            ),
          ],
        );
      },
    );
  }

  int _timeDiffMinutes(int t1, int t2) {
    final m1 = (t1 ~/ 100) * 60 + (t1 % 100);
    final m2 = (t2 ~/ 100) * 60 + (t2 % 100);
    return m2 - m1;
  }

  bool _isCurrentLesson(TimetableEntry e, DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    final startMins = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
    final endMins = (e.endTime ~/ 100) * 60 + (e.endTime % 100);
    return nowMins >= startMins && nowMins < endMins;
  }
}

// ── Lesson Tile (WebUntis grid style) ──────────────────────────────────────

class _LessonTile extends StatelessWidget {
  final TimetableEntry entry;
  final String? lessonNr;
  final bool isNow;
  final Color color;

  const _LessonTile({
    required this.entry,
    required this.lessonNr,
    required this.isNow,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Time column ──
          SizedBox(
            width: 52,
            child: Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    entry.startFormatted,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: isNow ? AppTheme.accent : AppTheme.textSecondary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    entry.endFormatted,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppTheme.textTertiary,
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),

          // ── Card ──
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: entry.isCancelled
                    ? AppTheme.danger.withValues(alpha: 0.06)
                    : AppTheme.surface,
                borderRadius: BorderRadius.circular(14),
                border: isNow
                    ? Border.all(color: AppTheme.accent.withValues(alpha: 0.6), width: 1.5)
                    : Border.all(color: AppTheme.border.withValues(alpha: 0.15)),
              ),
              child: Row(
                children: [
                  // Color accent bar
                  Container(
                    width: 4,
                    height: 72,
                    decoration: BoxDecoration(
                      color: entry.isCancelled ? AppTheme.danger.withValues(alpha: 0.5) : color,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        bottomLeft: Radius.circular(14),
                      ),
                    ),
                  ),

                  // Content
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Top row: subject + lesson nr
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  entry.displayName,
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                    color: entry.isCancelled
                                        ? AppTheme.textTertiary
                                        : AppTheme.textPrimary,
                                    decoration: entry.isCancelled
                                        ? TextDecoration.lineThrough
                                        : null,
                                    decorationColor: AppTheme.textTertiary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (lessonNr != null)
                                Container(
                                  width: 26, height: 26,
                                  decoration: BoxDecoration(
                                    color: isNow
                                        ? AppTheme.accent
                                        : color.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                  child: Center(
                                    child: Text(
                                      lessonNr!,
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: isNow ? Colors.white : color,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),

                          const SizedBox(height: 4),

                          // Bottom row: teacher, room, badges
                          Row(
                            children: [
                              if (entry.teacherName.isNotEmpty) ...[
                                Icon(CupertinoIcons.person_fill,
                                    size: 11, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
                                const SizedBox(width: 3),
                                Text(entry.teacherName,
                                    style: const TextStyle(fontSize: 13,
                                        color: AppTheme.textSecondary)),
                              ],
                              if (entry.teacherName.isNotEmpty && entry.roomName.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Container(
                                    width: 3, height: 3,
                                    decoration: const BoxDecoration(
                                      color: AppTheme.textTertiary,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                              if (entry.roomName.isNotEmpty) ...[
                                Icon(CupertinoIcons.location_solid,
                                    size: 11, color: AppTheme.textTertiary.withValues(alpha: 0.7)),
                                const SizedBox(width: 3),
                                Text(entry.roomName,
                                    style: const TextStyle(fontSize: 13,
                                        color: AppTheme.textSecondary)),
                              ],
                              const Spacer(),
                              if (entry.isExam)
                                _Badge(label: 'Prüfung', color: AppTheme.warning,
                                    icon: CupertinoIcons.doc_text_fill),
                              if (entry.isCancelled)
                                _Badge(label: 'Entfällt', color: AppTheme.danger,
                                    icon: CupertinoIcons.xmark_circle_fill),
                            ],
                          ),
                        ],
                      ),
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

// ── Shared Widgets ──────────────────────────────────────────────────────────

class _WeekNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WeekNavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 34, height: 34,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 15, color: AppTheme.textSecondary),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _Badge({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 3),
          Text(label,
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
