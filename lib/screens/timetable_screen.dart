import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../config/app_config.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import 'login_screen.dart';

// ── Data helpers ──────────────────────────────────────────────────────────────

enum _SlotKind { empty, normal, cancelled, replacement, exam, event }

class _SlotInfo {
  final TimetableEntry? display;
  final TimetableEntry? replacement;
  final bool isNow;
  final bool isPast;
  final _SlotKind kind;
  final List<HomeworkEntry> homework;
  const _SlotInfo({
    this.display,
    this.replacement,
    this.isNow = false,
    this.isPast = false,
    this.kind = _SlotKind.empty,
    this.homework = const [],
  });
  bool get isEmpty => kind == _SlotKind.empty || display == null;
}

// ── Week cache entry ──────────────────────────────────────────────────────────

enum _LoadState { idle, loading, done, error }

class _WeekData {
  _LoadState state;
  List<TimetableEntry> entries;
  List<HomeworkEntry> homework;
  String? error;
  _WeekData({
    this.state = _LoadState.idle,
    this.entries = const [],
    this.homework = const [],
    this.error,
  });
}

// ── Day status (for full-day cancelled / replacement columns) ─────────────────

enum _DayStatus { cancelled, replacement }

// ── Root screen ───────────────────────────────────────────────────────────────

class TimetableScreen extends StatefulWidget {
  static TimetableScreenState? of(BuildContext context) {
    final state = context.findAncestorStateOfType<TimetableScreenState>();
    return state;
  }

  static GlobalKey<TimetableScreenState> createKey() =>
      GlobalKey<TimetableScreenState>();
  final WebUntisService service;
  const TimetableScreen({super.key, required this.service});

  @override
  State<TimetableScreen> createState() => TimetableScreenState();
}

class TimetableScreenState extends State<TimetableScreen> {
  void showDetail(TimetableEntry entry, [TimetableEntry? replacement]) {
    _showDetail(entry, replacement);
  }

  void jumpToWeekAndDay({
    required int weekOffset,
    int? dayIndex,
    TimetableEntry? entry,
    TimetableEntry? replacement,
  }) {
    setState(() {
      _currentOffset = weekOffset;
      if (dayIndex != null) _selectedDay = dayIndex;
    });
    _pageController.animateToPage(
      _kBase + weekOffset,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
    if (entry != null) {
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) showDetail(entry, replacement);
      });
    }
  }

  static const int _kBase = 500;

  late final PageController _pageController;

  final Map<int, _WeekData> _cache = {};

  int _currentOffset = 0;
  int _selectedDay = -1;

  static List<String> get _dayLabels => AppConfig.dayLabels;
  static List<String> get _months => AppConfig.monthLabels;

  static const double _rowMinHeight = 78.0;
  static const double _connectedGap = 5.0;
  static const double _normalGap = 5.0;
  static const double _breakGap = 8.0;
  static const double _lunchGap = 14.0;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    // Am Wochenende (Sa/So) direkt nächste Woche anzeigen.
    final isWeekend = now.weekday >= 6;
    if (isWeekend) {
      _currentOffset = 1;
      _selectedDay = 0; // Montag
    } else {
      _selectedDay = now.weekday - 1;
    }

    _pageController = PageController(initialPage: _kBase + _currentOffset);

    _ensureLoaded(_currentOffset - 1);
    _ensureLoaded(_currentOffset);
    _ensureLoaded(_currentOffset + 1);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ── Week helpers ───────────────────────────────────────────────────────────

  DateTime _mondayForOffset(int offset) {
    final now = DateTime.now();
    // Use noon to avoid DST boundary issues at midnight.
    final today = DateTime(now.year, now.month, now.day, 12);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    final result = thisMonday.add(Duration(days: offset * 7));
    return DateTime(result.year, result.month, result.day);
  }

  DateTime _dayForOffset(int offset, int dayIndex) {
    final monday = _mondayForOffset(offset);
    return DateTime(monday.year, monday.month, monday.day + dayIndex);
  }

  bool _isThisWeek(int offset) => offset == 0;

  bool _isToday(int offset, int dayIndex) {
    final date = _dayForOffset(offset, dayIndex);
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(startOfYear).inDays;
    return ((diff + startOfYear.weekday) / 7).ceil();
  }

  // ── Cache / loading ────────────────────────────────────────────────────────

  void _ensureLoaded(int offset) {
    final existing = _cache[offset];
    if (existing != null && existing.state != _LoadState.idle) return;
    _cache[offset] = _WeekData(state: _LoadState.loading);
    _fetchOffset(offset);
  }

  Future<void> _fetchOffset(int offset) async {
    final weekStart = _mondayForOffset(offset);
    try {
      // Fetch timetable and homework in parallel.
      final results = await Future.wait([
        widget.service.getWeekTimetable(weekStart: weekStart),
        widget.service.getHomework(weekStart: weekStart),
      ]);
      if (!mounted) return;
      setState(() {
        _cache[offset] = _WeekData(
          state: _LoadState.done,
          entries: results[0] as List<TimetableEntry>,
          homework: results[1] as List<HomeworkEntry>,
        );
      });
    } on WebUntisException catch (e) {
      if (!mounted) return;
      if (e.isAuthError) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      setState(() {
        _cache[offset] = _WeekData(state: _LoadState.error, error: e.message);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cache[offset] = _WeekData(
          state: _LoadState.error,
          error: simplifyErrorMessage(e),
        );
      });
    }
  }

  void _retryOffset(int offset) {
    setState(() {
      _cache[offset] = _WeekData(state: _LoadState.loading);
    });
    _fetchOffset(offset);
  }

  // ── Page change ────────────────────────────────────────────────────────────

  void _onPageChanged(int page) {
    final offset = page - _kBase;
    final now = DateTime.now();
    setState(() {
      _currentOffset = offset;
      _selectedDay = (offset == 0 && now.weekday <= 5) ? now.weekday - 1 : -1;
    });
    _ensureLoaded(offset - 1);
    _ensureLoaded(offset);
    _ensureLoaded(offset + 1);
    _cache.removeWhere((k, _) => (k - offset).abs() > 3);
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() => _selectedDay = (now.weekday <= 5) ? now.weekday - 1 : -1);
    _pageController.animateToPage(
      _kBase,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Entry helpers ──────────────────────────────────────────────────────────

  List<TimetableEntry> _forDay(int offset, int dayIndex) {
    final date = _dayForOffset(offset, dayIndex);
    final dateInt = int.parse(
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
    );
    final entries = _cache[offset]?.entries ?? [];
    final result = entries.where((e) => e.date == dateInt).toList();

    return result;
  }

  bool _isHolidayWeek(int offset) {
    final data = _cache[offset];
    return data != null &&
        data.state == _LoadState.done &&
        data.entries.isEmpty;
  }

  bool _isSingleHolidayDay(int offset, int dayIndex) {
    if (_isHolidayWeek(offset)) return false;
    if (_forDay(offset, dayIndex).isNotEmpty) return false;
    for (int i = 0; i < 5; i++) {
      if (i != dayIndex && _forDay(offset, i).isNotEmpty) return true;
    }
    return false;
  }

  /// Returns true if every entry for this day is cancelled (and none are active).
  bool _isDayAllCancelled(int offset, int dayIndex) {
    final entries = _forDay(offset, dayIndex);
    if (entries.isEmpty) return false;
    final hasCancelled = entries.any((e) => e.isCancelled);
    final hasActive = entries.any((e) => !e.isCancelled);
    return hasCancelled && !hasActive;
  }

  /// Returns true when every active (non-cancelled) lesson for this day is a
  /// substitution or additional entry — i.e. the whole day is substituted.
  bool _isDayAllReplacement(int offset, int dayIndex) {
    final entries = _forDay(offset, dayIndex);
    if (entries.isEmpty) return false;

    final active = entries.where((e) => !e.isCancelled).toList();
    if (active.isEmpty)
      return false; // all cancelled → _isDayAllCancelled handles this

    final hasCancelledOriginals = entries.any((e) => e.isCancelled);
    final allActiveAreSubstitutes = active.every(
      (e) => e.isSubstitution || e.isAdditional,
    );

    // Show whole-day replacement column only when every lesson is a substitute
    // AND there are matching cancellations (classic full-day substitution).
    return hasCancelledOriginals && allActiveAreSubstitutes;
  }

  // ── Time maths ─────────────────────────────────────────────────────────────

  int _toMins(int packed) => (packed ~/ 100) * 60 + (packed % 100);
  int _addMinutes(int packed, int minutes) {
    final total = _toMins(packed) + minutes;
    return (total ~/ 60) * 100 + (total % 60);
  }

  /// Returns break windows derived from the API's TimeGrid.
  /// Falls back to [AppConfig.defaultBreakWindows] if the TimeGrid is empty.
  List<({int start, int end})> get _breakWindows {
    final grid = widget.service.timeGrid;
    if (grid.length < 2) return AppConfig.defaultBreakWindows;
    final breaks = <({int start, int end})>[];
    for (int i = 0; i < grid.length - 1; i++) {
      final gapMins = _toMins(grid[i + 1].startTime) - _toMins(grid[i].endTime);
      // A gap > 0 and ≤ 30 min between lessons is a short break.
      if (gapMins > 0 && gapMins <= 30) {
        breaks.add((start: grid[i].endTime, end: grid[i + 1].startTime));
      }
    }
    return breaks.isEmpty ? AppConfig.defaultBreakWindows : breaks;
  }

  bool _crossesFixedBreak(int endTime, int nextStart) {
    final endM = _toMins(endTime);
    final startM = _toMins(nextStart);
    for (final b in _breakWindows) {
      if (endM < _toMins(b.end) && startM > _toMins(b.start)) return true;
    }
    return false;
  }

  int? _findLunchGapIndex(
    List<int> sortedTimes,
    Map<int, int> endTimeForStart,
  ) {
    if (sortedTimes.length < 2) return null;
    int bestIndex = -1;
    int bestGap = 0;
    for (int i = 0; i < sortedTimes.length - 1; i++) {
      final t1 = sortedTimes[i];
      final t2 = sortedTimes[i + 1];
      final endT1 = endTimeForStart[t1] ?? _addMinutes(t1, 50);
      final gap = _toMins(t2) - _toMins(endT1);
      if (gap >= 30 && _toMins(endT1) >= 660 && _toMins(t2) <= 840) {
        if (gap > bestGap) {
          bestGap = gap;
          bestIndex = i;
        }
      }
    }
    return bestIndex >= 0 ? bestIndex : null;
  }

  _SlotInfo _buildSlot(
    int offset,
    int dayIndex,
    int startTime,
    DateTime now,
    Map<int, List<HomeworkEntry>> homeworkByLesson,
  ) {
    final dayEntries = _forDay(offset, dayIndex).where((e) {
      // Exact match (normal case)
      if (e.startTime == startTime) return true;
      // Multi-slot entry: this grid time falls within the entry's range
      return e.startTime < startTime && e.endTime > startTime;
    }).toList();

    if (dayEntries.isEmpty) return const _SlotInfo();

    final cancelled = dayEntries.where((e) => e.isCancelled).toList();
    final active = dayEntries.where((e) => !e.isCancelled).toList();

    TimetableEntry display;
    TimetableEntry? repl;
    _SlotKind kind;

    if (cancelled.isNotEmpty && active.isNotEmpty) {
      // Classic case: original cancelled + substitute active
      display = cancelled.first;
      repl = active.first;
      kind = _SlotKind.replacement;
    } else if (cancelled.isNotEmpty) {
      display = cancelled.first;
      repl = null;
      kind = _SlotKind.cancelled;
    } else {
      final substitutionOnlyEntries = active
          .where((e) => e.isSubstitution && !e.isAdditional)
          .toList();
      final additionalOnlyEntries = active
          .where((e) => e.isAdditional && !e.isSubstitution)
          .toList();
      final ambiguousEntries = active
          .where((e) => e.isSubstitution && e.isAdditional)
          .toList();
      final normalEntries = active
          .where((e) => !e.isAdditional && !e.isSubstitution)
          .toList();

      if (normalEntries.isNotEmpty &&
          (substitutionOnlyEntries.isNotEmpty ||
              additionalOnlyEntries.isNotEmpty ||
              ambiguousEntries.isNotEmpty)) {
        // Normal entry + special entry: show like Ersatz/Vertretung
        // (original struck through + replacement below).
        display = normalEntries.first;
        repl = additionalOnlyEntries.isNotEmpty
            ? additionalOnlyEntries.first
            : ambiguousEntries.isNotEmpty
            ? ambiguousEntries.first
            : substitutionOnlyEntries.first;
        kind = _SlotKind.replacement;
      } else {
        // All entries are special (or all normal). Prefer ADDITIONAL when
        // the API reports both flags, otherwise use SUBSTITUTION as the
        // main lesson.
        if (additionalOnlyEntries.isNotEmpty) {
          display = additionalOnlyEntries.first;
        } else if (ambiguousEntries.isNotEmpty) {
          display = ambiguousEntries.first;
        } else if (substitutionOnlyEntries.isNotEmpty) {
          display = substitutionOnlyEntries.first;
        } else {
          display = active.first;
        }
        repl = null;
        if (display.isExam) {
          kind = _SlotKind.exam;
        } else if (display.isSubstitution || display.isAdditional) {
          kind = _SlotKind.replacement;
        } else if (display.subjectName.isEmpty &&
            display.lessonText.isNotEmpty) {
          kind = _SlotKind.event;
        } else {
          kind = _SlotKind.normal;
        }
      }
    }

    final isNow = _isToday(offset, dayIndex) && _isCurrentLesson(display, now);
    final isPast = !isNow && (() {
      final day = _dayForOffset(offset, dayIndex);
      final today = DateTime(now.year, now.month, now.day);
      final lessonDay = DateTime(day.year, day.month, day.day);
      if (lessonDay.isBefore(today)) return true;
      if (lessonDay.isAtSameMomentAs(today)) {
        final nowMins = now.hour * 60 + now.minute;
        final endMins = (display.endTime ~/ 100) * 60 + (display.endTime % 100);
        return nowMins >= endMins;
      }
      return false;
    })();
    final homework = homeworkByLesson[display.lessonId] ?? [];
    return _SlotInfo(
      display: display,
      replacement: repl,
      isNow: isNow,
      isPast: isPast,
      kind: kind,
      homework: homework,
    );
  }

  /// Returns the single event entry covering ALL sortedTimes for this day,
  /// or null if no such entry exists.
  TimetableEntry? _getFullDayEvent(
    int offset,
    int dayIndex,
    List<int> sortedTimes,
  ) {
    if (sortedTimes.isEmpty) return null;
    final dayEntries = _forDay(offset, dayIndex);
    for (final e in dayEntries) {
      if (e.subjectName.isEmpty && e.lessonText.isNotEmpty && !e.isCancelled) {
        final coversAll = sortedTimes.every(
          (t) => e.startTime <= t && e.endTime > t,
        );
        if (coversAll) return e;
      }
    }
    return null;
  }

  bool _slotsMergeable(_SlotInfo a, _SlotInfo b) {
    if (a.isEmpty || b.isEmpty) return false;
    if (a.kind != b.kind) return false;
    final ea = a.display!, eb = b.display!;
    if (a.kind == _SlotKind.normal) {
      return ea.subjectName == eb.subjectName &&
          ea.teacherName == eb.teacherName;
    }
    return ea.subjectName == eb.subjectName && ea.lessonText == eb.lessonText;
  }

  void _showDetail(
    TimetableEntry entry,
    TimetableEntry? replacement, {
    List<HomeworkEntry> homework = const [],
  }) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(
        entry: entry,
        replacement: replacement,
        service: widget.service,
        homework: homework,
      ),
    );
  }

  bool _isCurrentLesson(TimetableEntry e, DateTime now) {
    final nowMins = now.hour * 60 + now.minute;
    final startMins = (e.startTime ~/ 100) * 60 + (e.startTime % 100);
    final endMins = (e.endTime ~/ 100) * 60 + (e.endTime % 100);
    return nowMins >= startMins && nowMins < endMins;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          _buildHeader(),
          const SizedBox(height: 10),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: _onPageChanged,
              itemBuilder: (context, page) {
                final offset = page - _kBase;
                return _WeekPage(
                  key: ValueKey(offset),
                  offset: offset,
                  state: this,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final weekStart = _mondayForOffset(_currentOffset);
    final weekEnd = weekStart.add(const Duration(days: 4));
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Stundenplan',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: context.appTextPrimary,
                  letterSpacing: -0.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${weekStart.day}. ${_months[weekStart.month - 1]} – '
                  '${weekEnd.day}. ${_months[weekEnd.month - 1]} ${weekEnd.year}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: context.appTextSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text(
                'KW ${_weekNumber(weekStart)}',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: context.appTextTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Week Page ─────────────────────────────────────────────────────────────────

class _WeekPage extends StatelessWidget {
  final int offset;
  final TimetableScreenState state;

  const _WeekPage({super.key, required this.offset, required this.state});

  @override
  Widget build(BuildContext context) {
    final data = state._cache[offset];
    final loadState = data?.state ?? _LoadState.loading;

    if (loadState == _LoadState.loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 14),
            SizedBox(height: 14),
            Text(
              'Stundenplan wird geladen…',
              style: TextStyle(color: context.appTextSecondary, fontSize: 14),
            ),
          ],
        ),
      );
    }

    if (loadState == _LoadState.error) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                CupertinoIcons.exclamationmark_triangle_fill,
                color: AppTheme.danger,
                size: 28,
              ),
              const SizedBox(height: 10),
              Text(
                data?.error ?? 'Unbekannter Fehler',
                style: TextStyle(color: context.appTextSecondary),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 14),
              CupertinoButton(
                color: AppTheme.accent,
                borderRadius: BorderRadius.circular(10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
                minimumSize: Size.zero,
                onPressed: () => state._retryOffset(offset),
                child: const Text(
                  'Erneut versuchen',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state._isHolidayWeek(offset)) {
      return _buildHolidayWeek(context);
    }

    return _buildWeekGrid(context);
  }

  Widget _buildHolidayWeek(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppTheme.orange.withValues(alpha: 0.35),
                  AppTheme.warning.withValues(alpha: 0.2),
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Text('🏖️', style: TextStyle(fontSize: 40)),
            ),
          ),
          const SizedBox(height: 22),
          Text(
            'Ferien',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: context.appTextPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'In dieser Woche ist kein Unterricht.',
            style: TextStyle(fontSize: 15, color: context.appTextSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'KW ${state._weekNumber(state._mondayForOffset(offset))} · Genieße die Zeit! ☀️',
            style: TextStyle(fontSize: 13, color: context.appTextTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekGrid(BuildContext context) {
    final entries = state._cache[offset]?.entries ?? [];

    final allTimes = <int>{};
    for (int d = 0; d < 5; d++) {
      for (final e in state._forDay(offset, d)) {
        allTimes.add(e.startTime);
      }
    }
    final sortedTimes = allTimes.toList()..sort();
    if (sortedTimes.isEmpty) return const SizedBox();
    final n = sortedTimes.length;

    final endTimeForStart = <int, int>{};
    for (final e in entries) {
      if (!endTimeForStart.containsKey(e.startTime) ||
          e.endTime > endTimeForStart[e.startTime]!) {
        endTimeForStart[e.startTime] = e.endTime;
      }
    }

    final lunchGapIndex = state._findLunchGapIndex(
      sortedTimes,
      endTimeForStart,
    );

    final timeConnected = List<bool>.filled(n > 0 ? n - 1 : 0, false);
    for (int i = 0; i < n - 1; i++) {
      final t1 = sortedTimes[i];
      final t2 = sortedTimes[i + 1];
      final endT1 = endTimeForStart[t1] ?? state._addMinutes(t1, 50);
      final gapMins = state._toMins(t2) - state._toMins(endT1);
      final isLunch = lunchGapIndex != null && i == lunchGapIndex;
      final isFixed = state._crossesFixedBreak(endT1, t2);
      timeConnected[i] = gapMins <= 5 && !isLunch && !isFixed;
    }

    double gapAfter(int i) {
      if (i >= n - 1) return 0;
      if (timeConnected[i]) return TimetableScreenState._connectedGap;
      if (lunchGapIndex != null && i == lunchGapIndex) {
        return TimetableScreenState._lunchGap;
      }
      final endT =
          endTimeForStart[sortedTimes[i]] ??
          state._addMinutes(sortedTimes[i], 50);
      if (state._crossesFixedBreak(endT, sortedTimes[i + 1])) {
        return TimetableScreenState._breakGap;
      }
      return TimetableScreenState._normalGap;
    }

    return Column(
      children: [
        // Day header tabs
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Row(
            children: [
              const SizedBox(width: 44),
              ...List.generate(5, (i) {
                final date = state._dayForOffset(offset, i);
                final isToday = state._isToday(offset, i);
                final isHoliday = state._isSingleHolidayDay(offset, i);
                final isDayOff = state._isDayAllCancelled(offset, i);
                final isDayRepl =
                    !isDayOff && state._isDayAllReplacement(offset, i);

                return Expanded(
                  child: GestureDetector(
                    onTap: isDayOff
                        ? null
                        : () {
                            // ignore: invalid_use_of_protected_member
                            state.setState(() => state._selectedDay = i);
                          },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppTheme.accent.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        children: [
                          Text(
                            TimetableScreenState._dayLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isToday
                                  ? AppTheme.accent
                                  : isDayOff
                                  ? AppTheme.danger.withValues(alpha: 0.8)
                                  : isDayRepl
                                  ? AppTheme.accent.withValues(alpha: 0.8)
                                  : isHoliday
                                  ? AppTheme.orange.withValues(alpha: 0.8)
                                  : context.appTextTertiary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Container(
                            width: 28,
                            height: 28,
                            decoration: isToday
                                ? const BoxDecoration(
                                    color: AppTheme.accent,
                                    shape: BoxShape.circle,
                                  )
                                : null,
                            child: Center(
                              child: Text(
                                '${date.day}',
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? Colors.white
                                      : isDayOff
                                      ? AppTheme.danger
                                      : isDayRepl
                                      ? AppTheme.accent
                                      : isHoliday
                                      ? AppTheme.orange
                                      : context.appTextPrimary,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Container(height: 0.5, color: context.appBorder.withValues(alpha: 0.3)),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: context.appSurface,
            onRefresh: () async {
              state._retryOffset(offset);
              while (state._cache[offset]?.state == _LoadState.loading) {
                await Future.delayed(const Duration(milliseconds: 50));
              }
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 32),
              child: _buildColumnarGrid(
                sortedTimes,
                timeConnected,
                gapAfter,
                endTimeForStart,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColumnarGrid(
    List<int> sortedTimes,
    List<bool> timeConnected,
    double Function(int) gapAfter,
    Map<int, int> endTimeForStart,
  ) {
    final n = sortedTimes.length;
    final now = DateTime.now();

    // Build lessonId → homework map once for all slots.
    final homeworkByLesson = <int, List<HomeworkEntry>>{};
    for (final hw in state._cache[offset]?.homework ?? []) {
      homeworkByLesson.putIfAbsent(hw.lessonId, () => []).add(hw);
    }

    // Check if today is visible in this week
    final hasTodayColumn = List.generate(
      5,
      (i) => state._isToday(offset, i),
    ).any((v) => v);

    return Stack(
      clipBehavior: Clip.none,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time labels column
            SizedBox(
              width: 44,
              child: Column(
                children: [
                  for (int i = 0; i < n; i++) ...[
                    _TimeLabel(
                      startTime: sortedTimes[i],
                      lessonNr: state.widget.service.getLessonNumber(
                        sortedTimes[i],
                      ),
                      height: TimetableScreenState._rowMinHeight,
                    ),
                    if (i < n - 1) SizedBox(height: gapAfter(i)),
                  ],
                ],
              ),
            ),
            // Day columns
            ...List.generate(5, (dayIndex) {
              final isHoliday = state._isSingleHolidayDay(offset, dayIndex);
              final isDayOff = state._isDayAllCancelled(offset, dayIndex);
              final isDayRepl =
                  !isDayOff && state._isDayAllReplacement(offset, dayIndex);

              final totalHeight =
                  n * TimetableScreenState._rowMinHeight +
                  List.generate(
                    n - 1,
                    (i) => gapAfter(i),
                  ).fold(0.0, (a, b) => a + b);

              if (isHoliday) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: _HolidayColumn(totalHeight: totalHeight),
                  ),
                );
              }

              // Full-day event (e.g. "Veranstaltung" 07:50–16:45)
              final fullDayEvent = state._getFullDayEvent(
                offset,
                dayIndex,
                sortedTimes,
              );
              if (fullDayEvent != null) {
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: () => state._showDetail(fullDayEvent, null),
                      behavior: HitTestBehavior.opaque,
                      child: _EventColumn(
                        totalHeight: totalHeight,
                        label: fullDayEvent.lessonText,
                      ),
                    ),
                  ),
                );
              }

              if (isDayOff || isDayRepl) {
                final entries = state._forDay(offset, dayIndex);
                final cancelled = entries.where((e) => e.isCancelled).toList();
                final active = entries.where((e) => !e.isCancelled).toList();
                TimetableEntry? display;
                TimetableEntry? replacement;
                if (isDayOff && cancelled.isNotEmpty) {
                  display = cancelled.first;
                } else if (isDayRepl &&
                    cancelled.isNotEmpty &&
                    active.isNotEmpty) {
                  display = cancelled.first;
                  replacement = active.first;
                }
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: GestureDetector(
                      onTap: !isDayOff && display != null
                          ? () => state._showDetail(display!, replacement)
                          : null,
                      behavior: HitTestBehavior.opaque,
                      child: _DayStatusColumn(
                        totalHeight: totalHeight,
                        kind: isDayOff
                            ? _DayStatus.cancelled
                            : _DayStatus.replacement,
                      ),
                    ),
                  ),
                );
              }

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: _buildDayColumn(
                    dayIndex: dayIndex,
                    sortedTimes: sortedTimes,
                    timeConnected: timeConnected,
                    gapAfter: gapAfter,
                    now: now,
                    homeworkByLesson: homeworkByLesson,
                  ),
                ),
              );
            }),
          ],
        ),
        // Full-width time indicator — spans across all columns
        if (hasTodayColumn)
          _TimeIndicator(
            offset: offset,
            sortedTimes: sortedTimes,
            endTimeForStart: endTimeForStart,
            gapAfter: gapAfter,
            state: state,
          ),
      ],
    );
  }

  Widget _buildDayColumn({
    required int dayIndex,
    required List<int> sortedTimes,
    required List<bool> timeConnected,
    required double Function(int) gapAfter,
    required DateTime now,
    required Map<int, List<HomeworkEntry>> homeworkByLesson,
  }) {
    final n = sortedTimes.length;
    final slots = List<_SlotInfo>.generate(
      n,
      (idx) => state._buildSlot(
        offset,
        dayIndex,
        sortedTimes[idx],
        now,
        homeworkByLesson,
      ),
    );

    final widgets = <Widget>[];
    int i = 0;
    while (i < n) {
      final groupStart = i;
      while (i < n - 1 &&
          timeConnected[i] &&
          state._slotsMergeable(slots[i], slots[i + 1])) {
        i++;
      }
      final groupEnd = i;

      final groupLen = groupEnd - groupStart + 1;
      final double groupHeight =
          groupLen * TimetableScreenState._rowMinHeight +
          (groupLen - 1) * TimetableScreenState._connectedGap;

      final groupSlots = [
        for (int k = groupStart; k <= groupEnd; k++) slots[k],
      ];
      final allEmpty = groupSlots.every((s) => s.isEmpty);

      if (allEmpty) {
        widgets.add(SizedBox(height: groupHeight));
      } else {
        widgets.add(
          _MergedCell(
            slots: groupSlots,
            height: groupHeight,
            onTap: (slotGroup) {
              final displaySlot = slotGroup.firstWhere(
                (s) => s.display != null,
                orElse: () => slotGroup.first,
              );
              if (displaySlot.display != null) {
                final mergedHomework = <HomeworkEntry>[];
                final seenHomeworkIds = <int>{};
                for (final slot in slotGroup) {
                  for (final hw in slot.homework) {
                    if (seenHomeworkIds.add(hw.id)) {
                      mergedHomework.add(hw);
                    }
                  }
                }

                final mergedEntry = _buildMergedEntry(slotGroup);
                state._showDetail(
                  mergedEntry,
                  displaySlot.replacement,
                  homework: mergedHomework,
                );
              }
            },
          ),
        );
      }

      if (groupEnd < n - 1) {
        widgets.add(SizedBox(height: gapAfter(groupEnd)));
      }
      i = groupEnd + 1;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: widgets,
    );
  }

  TimetableEntry _buildMergedEntry(List<_SlotInfo> slots) {
    final first = slots.firstWhere((s) => s.display != null).display!;
    final last = slots.lastWhere((s) => s.display != null).display!;
    return TimetableEntry(
      id: first.id,
      lessonId: first.lessonId,
      date: first.date,
      startTime: first.startTime,
      endTime: last.endTime,
      subjectName: first.subjectName,
      subjectLong: first.subjectLong,
      teacherName: first.teacherName,
      roomName: first.roomName,
      cellState: first.cellState,
      lessonText: first.lessonText,
      isCancelled: first.isCancelled,
      isExam: first.isExam,
      isSubstitution: first.isSubstitution,
      isAdditional: first.isAdditional,
      originalSubjectName: first.originalSubjectName,
      originalSubjectLong: first.originalSubjectLong,
      originalTeacherName: first.originalTeacherName,
    );
  }
}

// ── Time Indicator ────────────────────────────────────────────────────────────

class _TimeIndicator extends StatelessWidget {
  final int offset;
  final List<int> sortedTimes;
  final Map<int, int> endTimeForStart;
  final double Function(int) gapAfter;
  final TimetableScreenState state;

  const _TimeIndicator({
    required this.offset,
    required this.sortedTimes,
    required this.endTimeForStart,
    required this.gapAfter,
    required this.state,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final nowMins = now.hour * 60 + now.minute;

    final firstStartMins = state._toMins(sortedTimes.first);
    final lastEndMins = state._toMins(
      endTimeForStart[sortedTimes.last] ??
          state._addMinutes(sortedTimes.last, 50),
    );

    // Only visible while within today's schedule
    if (nowMins < firstStartMins || nowMins > lastEndMins) {
      return const SizedBox.shrink();
    }

    // Walk through slots to compute y position
    double y = 0;
    final n = sortedTimes.length;
    for (int i = 0; i < n; i++) {
      final slotStartMins = state._toMins(sortedTimes[i]);
      final slotEndMins = state._toMins(
        endTimeForStart[sortedTimes[i]] ??
            state._addMinutes(sortedTimes[i], 50),
      );

      if (nowMins <= slotEndMins) {
        final slotDuration = (slotEndMins - slotStartMins).clamp(1, 9999);
        final elapsed = (nowMins - slotStartMins).clamp(0, slotDuration);
        y += TimetableScreenState._rowMinHeight * (elapsed / slotDuration);
        break;
      } else {
        y += TimetableScreenState._rowMinHeight;
        if (i < n - 1) y += gapAfter(i);
      }
    }

    final todayIndex = List.generate(
      5,
      (i) => state._isToday(offset, i),
    ).indexWhere((v) => v);

    const double thinLine = 1.5;
    const double thickLine = 3.5;
    const double dotSize = 7.0;
    // 44px time-label column + 2px padding on each side of each day column
    const double timeLabelWidth = 44.0;
    const double colPadding = 2.0;
    final lineColor = AppTheme.accent.withValues(alpha: 0.85);

    return Positioned(
      top: y - 1,
      left: 0,
      right: 0,
      child: IgnorePointer(
        child: LayoutBuilder(
          builder: (_, constraints) {
            final totalWidth = constraints.maxWidth;
            // Width available for the 5 day columns (after time-label area)
            final dayAreaWidth = totalWidth - timeLabelWidth;
            final colWidth = dayAreaWidth / 5;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.centerLeft,
              children: [
                // Single continuous thin line across full width
                Positioned(
                  left: dotSize,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: Center(
                    child: Container(height: thinLine, color: lineColor),
                  ),
                ),
                // Thicker overlay on today's column only (no padding gaps)
                if (todayIndex >= 0)
                  Positioned(
                    left: timeLabelWidth + todayIndex * colWidth + colPadding,
                    width: colWidth - colPadding * 2,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: Container(
                        height: thickLine,
                        decoration: BoxDecoration(
                          color: lineColor,
                          borderRadius: BorderRadius.circular(thickLine / 2),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}

// ── Holiday Column ────────────────────────────────────────────────────────────

class _HolidayColumn extends StatelessWidget {
  final double totalHeight;
  const _HolidayColumn({required this.totalHeight});
  @override
  Widget build(BuildContext context) {
    return Container(
      height: totalHeight,
      decoration: BoxDecoration(
        color: AppTheme.orange.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.orange.withValues(alpha: 0.28)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: const [
              Text('🏖️', style: TextStyle(fontSize: 20)),
              SizedBox(height: 4),
              Text(
                'Ferien',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.orange,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Day Status Column (ganzer Tag Entfall / Vertretung) ───────────────────────

class _DayStatusColumn extends StatelessWidget {
  final double totalHeight;
  final _DayStatus kind;
  const _DayStatusColumn({required this.totalHeight, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isCancelled = kind == _DayStatus.cancelled;
    final color = isCancelled ? AppTheme.danger : AppTheme.accent;
    final label = isCancelled ? 'Entfall' : 'Vertretung';
    final icon = isCancelled
        ? CupertinoIcons.xmark_circle_fill
        : CupertinoIcons.arrow_right_arrow_left;

    return Container(
      height: totalHeight,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Center(child: Icon(icon, size: 14, color: color)),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Event Column (Ganztages-Veranstaltung, blau) ──────────────────────────────

class _EventColumn extends StatelessWidget {
  final double totalHeight;
  final String label;
  const _EventColumn({required this.totalHeight, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: totalHeight,
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.30)),
      ),
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 14, left: 6, right: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Icon(
                    CupertinoIcons.calendar_badge_plus,
                    size: 14,
                    color: AppTheme.accent,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label.isNotEmpty ? label : 'Veranstaltung',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.accent,
                ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Merged Cell ───────────────────────────────────────────────────────────────

class _MergedCell extends StatelessWidget {
  final List<_SlotInfo> slots;
  final double height;
  final void Function(List<_SlotInfo> slots) onTap;
  const _MergedCell({
    required this.slots,
    required this.height,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = slots.firstWhere(
      (s) => !s.isEmpty,
      orElse: () => slots.first,
    );
    if (primary.isEmpty) return SizedBox(height: height);

    final entry = primary.display!;
    final subjectColor = AppTheme.colorForSubject(entry.subjectName);
    final hasHomework = slots.any((s) => s.homework.isNotEmpty);
    final isPast = slots.any((s) => s.isPast);

    // Slightly lighter than before in both themes.
    final cellBg = Color.alphaBlend(
      Colors.white.withValues(
        alpha: Theme.of(context).brightness == Brightness.dark ? 0.10 : 0.22,
      ),
      context.appCard,
    );

    final bool isSpecial =
        entry.isExam ||
        entry.isCancelled ||
        primary.kind == _SlotKind.replacement ||
        primary.kind == _SlotKind.event ||
        entry.isSubstitution ||
        entry.isAdditional ||
        hasHomework;

    Color? highlightColor;
    if (entry.isCancelled) {
      highlightColor = AppTheme.danger;
    } else if (entry.isExam) {
      highlightColor = AppTheme.warning;
    } else if (primary.kind == _SlotKind.replacement ||
        entry.isSubstitution ||
        entry.isAdditional) {
      highlightColor = (entry.isAdditional && !entry.isSubstitution)
          ? AppTheme.accent
          : AppTheme.orange;
    } else if (primary.kind == _SlotKind.event || entry.lessonText.isNotEmpty) {
      highlightColor = AppTheme.tint;
    } else if (hasHomework) {
      highlightColor = AppTheme.accentSoft;
    }

    final borderColor = isSpecial
        ? (highlightColor ?? AppTheme.accent).withValues(alpha: 0.78)
        : context.appBorder.withValues(alpha: 0.25);
    final borderWidth = isSpecial ? 1.6 : 1.1;

    // Jede Cell ist tappable, sofern ein Eintrag existiert
    final isTappable = !primary.isEmpty;

    return GestureDetector(
      onTap: isTappable ? () => onTap(slots) : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: isPast
              ? Color.alphaBlend(Colors.black.withValues(alpha: 0.18), cellBg)
              : cellBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isPast
                ? borderColor.withValues(alpha: borderColor.a * 0.55)
                : borderColor,
            width: borderWidth,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Opacity(
            opacity: isPast ? 0.55 : 1.0,
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 3,
                color: entry.isCancelled
                    ? AppTheme.danger.withValues(alpha: 0.7)
                    : entry.isExam
                    ? AppTheme.warning.withValues(alpha: 0.8)
                    : (primary.kind == _SlotKind.replacement &&
                          !entry.isCancelled)
                    // Zusatzstunde → blue, Vertretung/Substitute-only → orange
                    ? ((primary.replacement?.isAdditional == true ||
                              entry.isAdditional)
                          ? AppTheme.accent.withValues(alpha: 0.75)
                          : AppTheme.orange.withValues(alpha: 0.75))
                    : subjectColor.withValues(alpha: 0.55),
              ),
              Expanded(
                child: _SlotContent(slot: primary, isTappable: isTappable),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }
}

// ── Slot Content ──────────────────────────────────────────────────────────────

class _SlotContent extends StatelessWidget {
  final _SlotInfo slot;
  final bool isTappable;
  const _SlotContent({required this.slot, required this.isTappable});

  @override
  Widget build(BuildContext context) {
    if (slot.isEmpty) return const SizedBox();

    final entry = slot.display!;
    final replacement = slot.replacement;
    final hasReplacement = replacement != null;
    final replIsAdditionalOnly =
        replacement?.isAdditional == true &&
        replacement?.isSubstitution == false &&
        !entry.isCancelled;

    IconData? statusIcon;
    Color? statusIconColor;
    if (entry.isCancelled && !hasReplacement) {
      statusIcon = CupertinoIcons.xmark_circle_fill;
      statusIconColor = AppTheme.danger;
    } else if (entry.isExam) {
      statusIcon = CupertinoIcons.doc_text_fill;
      statusIconColor = AppTheme.warning;
    } else if (hasReplacement) {
      statusIcon = replIsAdditionalOnly
          ? CupertinoIcons.plus_circle_fill
          : CupertinoIcons.arrow_right_arrow_left;
      statusIconColor = replIsAdditionalOnly
          ? AppTheme.accent
          : AppTheme.colorForSubject(replacement!.subjectName);
    } else if (entry.isAdditional) {
      // Substitute-only Zusatzstunde: no cancelled original in the response
      statusIcon = CupertinoIcons.plus_circle_fill;
      statusIconColor = AppTheme.accent;
    } else if (entry.isSubstitution) {
      // Substitute-only Vertretung
      statusIcon = CupertinoIcons.arrow_right_arrow_left;
      statusIconColor = AppTheme.orange;
    } else if (entry.lessonText.isNotEmpty) {
      statusIcon = CupertinoIcons.doc_plaintext;
      statusIconColor = AppTheme.tint;
    }

    final hasHomework = slot.homework.isNotEmpty;

    final replColor = hasReplacement
        ? AppTheme.colorForSubject(replacement.subjectName)
        : AppTheme.orange;

    final bool isCancelledReplacement = entry.isCancelled && hasReplacement;
    final bool isReplaced =
        !isCancelledReplacement && (entry.isCancelled || hasReplacement);

    final bool isExam = entry.isExam;
    final Color examTextPrimary = isExam
        ? AppTheme.warning
        : context.appTextPrimary;
    final Color examTextSecondary = isExam
        ? AppTheme.warning.withValues(alpha: 0.8)
        : context.appTextSecondary;
    final Color examTextTertiary = isExam
        ? AppTheme.warning.withValues(alpha: 0.68)
        : context.appTextTertiary;

    // Single entry that carries both the original and the new subject
    // inside the same period (Zusatzstunde / Vertretung without a
    // separate cancelled entry).
    final bool hasInlineOriginal =
        !hasReplacement &&
        (entry.isAdditional || entry.isSubstitution) &&
        entry.originalSubjectName.isNotEmpty &&
        entry.originalSubjectName != entry.subjectName;
    final bool hideInlineOriginalSubject =
        hasInlineOriginal && entry.isSubstitution && !entry.isAdditional;
    final bool isPureSubstitution =
        entry.isSubstitution && !entry.isAdditional && !hasReplacement;
    final bool isPureAdditional =
        entry.isAdditional && !entry.isSubstitution && !hasReplacement;

    return ClipRect(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 3, 4, 3),
        child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (hasInlineOriginal && !hideInlineOriginalSubject) ...[
                  // ── Inline original: original subject struck through ──────
                  Text(
                    entry.originalSubjectName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isExam
                          ? AppTheme.warning
                          : AppTheme.danger.withValues(alpha: 0.65),
                      decoration: TextDecoration.lineThrough,
                      decorationColor: AppTheme.danger.withValues(alpha: 0.75),
                      decorationThickness: 2.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  // ── New subject in its subject color ──────────────────────
                  Text(
                    entry.subjectName,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isExam
                          ? examTextPrimary
                          : (isPureAdditional
                                ? AppTheme.accent
                                : AppTheme.colorForSubject(entry.subjectName)),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (entry.teacherName.isNotEmpty)
                    Text(
                      entry.teacherName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isExam
                            ? examTextSecondary
                            : (isPureAdditional
                                  ? AppTheme.accent.withValues(alpha: 0.75)
                                  : AppTheme.colorForSubject(
                                      entry.subjectName,
                                    ).withValues(alpha: 0.85)),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ] else ...[
                  // ── Original / normal subject (struck through when replaced)
                  Text(
                    hideInlineOriginalSubject
                        ? entry.originalSubjectName
                        : (entry.subjectName.isNotEmpty
                              ? entry.subjectName
                              : entry.lessonText),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: isExam
                          ? examTextPrimary
                          : (hideInlineOriginalSubject ||
                                    isPureSubstitution ||
                                    isPureAdditional
                                ? (hideInlineOriginalSubject ||
                                          isPureSubstitution
                                      ? AppTheme.orange
                                      : AppTheme.accent)
                                : isCancelledReplacement
                                ? AppTheme.danger
                                : isReplaced
                                ? AppTheme.danger.withValues(alpha: 0.65)
                                : context.appTextPrimary),
                      decoration: hideInlineOriginalSubject
                          ? TextDecoration.lineThrough
                          : isReplaced
                          ? TextDecoration.lineThrough
                          : null,
                      decorationColor: AppTheme.danger.withValues(alpha: 0.75),
                      decorationThickness: 2.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  // ── Teacher of original / substitution / additional entry
                  if ((isPureSubstitution ||
                          isPureAdditional ||
                          (!hideInlineOriginalSubject &&
                              entry.teacherName.isNotEmpty &&
                              (!hasReplacement || isCancelledReplacement))) &&
                      entry.teacherName.isNotEmpty) ...[
                    Text(
                      entry.teacherName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isExam
                            ? examTextTertiary
                            : (isPureSubstitution
                                  ? AppTheme.orange.withValues(alpha: 0.72)
                                  : isPureAdditional
                                  ? AppTheme.accent.withValues(alpha: 0.82)
                                  : isCancelledReplacement
                                  ? AppTheme.danger.withValues(alpha: 0.82)
                                  : isReplaced
                                  ? AppTheme.danger.withValues(alpha: 0.78)
                                  : context.appTextSecondary),
                        decoration: isPureSubstitution
                            ? null
                            : isPureAdditional
                            ? null
                            : isReplaced
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppTheme.danger.withValues(
                          alpha: 0.65,
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if ((isPureSubstitution ||
                          isPureAdditional ||
                          (!hideInlineOriginalSubject &&
                              entry.roomName.isNotEmpty &&
                              (!hasReplacement || isCancelledReplacement))) &&
                      entry.roomName.isNotEmpty) ...[
                    Text(
                      entry.roomName,
                      style: TextStyle(
                        fontSize: 10,
                        color: isExam
                            ? examTextTertiary
                            : (isPureSubstitution
                                  ? AppTheme.orange.withValues(alpha: 0.72)
                                  : isPureAdditional
                                  ? AppTheme.accent.withValues(alpha: 0.82)
                                  : isCancelledReplacement
                                  ? AppTheme.danger.withValues(alpha: 0.82)
                                  : isReplaced
                                  ? AppTheme.danger.withValues(alpha: 0.78)
                                  : context.appTextSecondary),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  // ── Replacement subject + teacher (Untis style) ───────────
                  if (hasReplacement && !isCancelledReplacement) ...[
                    const SizedBox(height: 2),
                    Text(
                      replacement.subjectName.isNotEmpty
                          ? replacement.subjectName
                          : replacement.lessonText,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: replColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (replacement.teacherName.isNotEmpty)
                      Text(
                        replacement.teacherName,
                        style: TextStyle(
                          fontSize: 10,
                          color: replColor.withValues(alpha: 0.86),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                ],
              ],
            ),
            // Bottom-right icon row: homework house + status icon
            Positioned(
              right: 0,
              bottom: 0,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (hasHomework) ...[
                    Icon(
                      CupertinoIcons.house_fill,
                      size: 11,
                      color: context.appTextTertiary,
                    ),
                    if (statusIcon != null) const SizedBox(width: 3),
                  ],
                  if (statusIcon != null)
                    Icon(statusIcon, size: 11, color: statusIconColor),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Detail Bottom Sheet ───────────────────────────────────────────────────────

class _DetailSheet extends StatelessWidget {
  final TimetableEntry entry;
  final TimetableEntry? replacement;
  final WebUntisService service;
  final List<HomeworkEntry> homework;
  const _DetailSheet({
    required this.entry,
    required this.replacement,
    required this.service,
    this.homework = const [],
  });

  @override
  Widget build(BuildContext context) {
    // Single entry with both original + new subject inline (no separate
    // replacement entry). Common for Zusatzstunde / Vertretung in student view.
    final bool hasInlineOriginal =
        replacement == null &&
        (entry.isAdditional || entry.isSubstitution) &&
        entry.originalSubjectName.isNotEmpty &&
        entry.originalSubjectName != entry.subjectName;
    final replIsAdditionalOnly =
        replacement?.isAdditional == true &&
        replacement?.isSubstitution == false &&
        !entry.isCancelled;
    final entryIsAdditionalOnly =
        entry.isAdditional && !entry.isSubstitution && !entry.isCancelled;

    final color = entry.isCancelled
        ? AppTheme.danger
        : entry.isExam
        ? AppTheme.warning
        : hasInlineOriginal
        ? AppTheme.colorForSubject(entry.originalSubjectName)
        : AppTheme.colorForSubject(entry.subjectName);

    // Header subject: show the original (struck through) when inline original,
    // otherwise show the entry's own subject.
    final headerName = hasInlineOriginal
        ? (entry.originalSubjectLong.isNotEmpty
              ? entry.originalSubjectLong
              : entry.originalSubjectName)
        : entry.displayName;
    final headerSub = hasInlineOriginal
        ? (entry.originalSubjectName != entry.originalSubjectLong &&
                  entry.originalSubjectLong.isNotEmpty
              ? entry.originalSubjectLong
              : '')
        : (entry.subjectName.isNotEmpty &&
                  entry.subjectLong.isNotEmpty &&
                  entry.subjectName != entry.subjectLong
              ? entry.subjectLong
              : '');

    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: context.appBorder,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Center(
                  child: Text(
                    hasInlineOriginal
                        ? entry.originalSubjectName[0]
                        : (entry.subjectName.isNotEmpty
                              ? entry.subjectName[0]
                              : '?'),
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerName,
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: hasInlineOriginal
                            ? AppTheme.danger.withValues(alpha: 0.65)
                            : context.appTextPrimary,
                        decoration: hasInlineOriginal
                            ? TextDecoration.lineThrough
                            : null,
                        decorationColor: AppTheme.danger.withValues(
                          alpha: 0.75,
                        ),
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (headerSub.isNotEmpty)
                      Text(
                        headerSub,
                        style: TextStyle(
                          fontSize: 13,
                          color: hasInlineOriginal
                              ? AppTheme.danger.withValues(alpha: 0.5)
                              : context.appTextSecondary,
                          decoration: hasInlineOriginal
                              ? TextDecoration.lineThrough
                              : null,
                          decorationColor: AppTheme.danger.withValues(
                            alpha: 0.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (entry.isCancelled)
                _SheetBadge(
                  label: 'Entfällt',
                  color: AppTheme.danger,
                  icon: CupertinoIcons.xmark_circle_fill,
                )
              else if (entry.isExam)
                _SheetBadge(
                  label: 'Prüfung',
                  color: AppTheme.warning,
                  icon: CupertinoIcons.doc_text_fill,
                )
              else if (entry.isAdditional)
                _SheetBadge(
                  label: 'Zusatzstunde',
                  color: AppTheme.accent,
                  icon: CupertinoIcons.plus_circle_fill,
                )
              else if (entry.isSubstitution)
                _SheetBadge(
                  label: 'Vertretung',
                  color: AppTheme.orange,
                  icon: CupertinoIcons.arrow_right_arrow_left,
                )
              // When the display entry is the unchanged original and the
              // replacement holds the Zusatzstunde / Vertretung flag:
              else if (replIsAdditionalOnly)
                _SheetBadge(
                  label: 'Zusatzstunde',
                  color: AppTheme.accent,
                  icon: CupertinoIcons.plus_circle_fill,
                )
              else if (replacement?.isSubstitution == true)
                _SheetBadge(
                  label: 'Vertretung',
                  color: AppTheme.orange,
                  icon: CupertinoIcons.arrow_right_arrow_left,
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 0.5, color: context.appBorder.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          _InfoRow(
            icon: CupertinoIcons.clock,
            label: 'Zeit',
            value: '${entry.startFormatted} – ${entry.endFormatted}',
          ),
          // When hasInlineOriginal the teacher/room belong to the NEW
          // subject and are shown inside the Zusatzstunde card below.
          if (entry.teacherName.isNotEmpty && !hasInlineOriginal) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: CupertinoIcons.person,
              label: entry.isSubstitution && !entry.isAdditional
                  ? 'Vertretung'
                  : 'Lehrer',
              value: entry.teacherName,
              valueColor: entry.isSubstitution && !entry.isAdditional
                  ? AppTheme.orange.withValues(alpha: 0.85)
                  : null,
            ),
          ],
          if (entry.roomName.isNotEmpty && !hasInlineOriginal) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: CupertinoIcons.location,
              label: 'Raum',
              value: entry.roomName,
            ),
          ],
          if (entry.lessonText.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: context.appBorder.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  CupertinoIcons.doc_plaintext,
                  size: 14,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Notiz',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: context.appCard,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                entry.lessonText,
                style: TextStyle(
                  fontSize: 14,
                  color: context.appTextPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (homework.isNotEmpty) ...[
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: context.appBorder.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  CupertinoIcons.house_fill,
                  size: 14,
                  color: AppTheme.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  'Hausaufgaben',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (final hw in homework) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 6),
                decoration: BoxDecoration(
                  color: context.appCard,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: AppTheme.accent.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hw.text,
                      style: TextStyle(
                        fontSize: 14,
                        color: context.appTextPrimary,
                        height: 1.4,
                      ),
                    ),
                    if (hw.dueDate > 0) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            CupertinoIcons.calendar,
                            size: 11,
                            color: context.appTextTertiary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Fällig: ${hw.dueDateFormatted}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appTextTertiary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
          if (replacement != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: context.appBorder.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  replIsAdditionalOnly
                      ? CupertinoIcons.plus_circle_fill
                      : CupertinoIcons.arrow_right_arrow_left,
                  size: 14,
                  color: replIsAdditionalOnly
                      ? AppTheme.accent
                      : AppTheme.colorForSubject(replacement!.subjectName),
                ),
                const SizedBox(width: 6),
                Text(
                  replIsAdditionalOnly ? 'Zusatzstunde' : 'Ersatz',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.appCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.colorForSubject(
                    replacement!.subjectName,
                  ).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.colorForSubject(
                            replacement!.subjectName,
                          ),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          replacement!.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (replacement!.teacherName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: CupertinoIcons.person,
                      label: 'Lehrer',
                      value: replacement!.teacherName,
                      small: true,
                    ),
                  ],
                  if (replacement!.roomName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: CupertinoIcons.location,
                      label: 'Raum',
                      value: replacement!.roomName,
                      small: true,
                    ),
                  ],
                  if (replacement!.lessonText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      replacement!.lessonText,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
          // ── Inline original → new subject (single entry with both) ────
          if (hasInlineOriginal) ...[
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: context.appBorder.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  entryIsAdditionalOnly
                      ? CupertinoIcons.plus_circle_fill
                      : CupertinoIcons.arrow_right_arrow_left,
                  size: 14,
                  color: entryIsAdditionalOnly
                      ? AppTheme.accent
                      : AppTheme.colorForSubject(entry.subjectName),
                ),
                const SizedBox(width: 6),
                Text(
                  entryIsAdditionalOnly
                      ? 'Zusatzstunde'
                      : 'Ersatz / Vertretung',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: context.appCard,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppTheme.colorForSubject(
                    entry.subjectName,
                  ).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: AppTheme.colorForSubject(entry.subjectName),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.displayName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  if (entry.teacherName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: CupertinoIcons.person,
                      label: 'Lehrer',
                      value: entry.teacherName,
                      small: true,
                    ),
                  ],
                  if (entry.roomName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _InfoRow(
                      icon: CupertinoIcons.location,
                      label: 'Raum',
                      value: entry.roomName,
                      small: true,
                    ),
                  ],
                  if (entry.lessonText.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Text(
                      entry.lessonText,
                      style: TextStyle(
                        fontSize: 13,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

class _SheetBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _SheetBadge({
    required this.label,
    required this.color,
    required this.icon,
  });
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color),
        const SizedBox(width: 5),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    ),
  );
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final bool small;
  final Color? valueColor;
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.small = false,
    this.valueColor,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: small ? 12 : 14, color: context.appTextTertiary),
      const SizedBox(width: 8),
      Text(
        '$label  ',
        style: TextStyle(
          fontSize: small ? 12 : 13,
          color: context.appTextTertiary,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: small ? 12 : 13,
            fontWeight: FontWeight.w500,
            color: valueColor ?? context.appTextSecondary,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    ],
  );
}

class _TimeLabel extends StatelessWidget {
  final int startTime;
  final String? lessonNr;
  final double height;
  const _TimeLabel({
    required this.startTime,
    required this.lessonNr,
    required this.height,
  });
  @override
  Widget build(BuildContext context) {
    final h = (startTime ~/ 100).toString().padLeft(2, '0');
    final m = (startTime % 100).toString().padLeft(2, '0');
    return SizedBox(
      height: height,
      child: Padding(
        padding: const EdgeInsets.only(top: 6, right: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (lessonNr != null)
              Text(
                lessonNr!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: context.appTextTertiary,
                ),
              ),
            Text(
              '$h:$m',
              style: TextStyle(
                fontSize: 10,
                color: context.appTextTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
