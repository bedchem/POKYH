import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'login_screen.dart';

// ── Data helpers ──────────────────────────────────────────────────────────────

enum _SlotKind { empty, normal, cancelled, replacement, exam, event }

class _SlotInfo {
  final TimetableEntry? display;
  final TimetableEntry? replacement;
  final bool isNow;
  final _SlotKind kind;
  const _SlotInfo({
    this.display,
    this.replacement,
    this.isNow = false,
    this.kind = _SlotKind.empty,
  });
  bool get isEmpty => kind == _SlotKind.empty || display == null;
}

// ── Week cache entry ──────────────────────────────────────────────────────────

enum _LoadState { idle, loading, done, error }

class _WeekData {
  _LoadState state;
  List<TimetableEntry> entries;
  String? error;
  _WeekData({
    this.state = _LoadState.idle,
    this.entries = const [],
    this.error,
  });
}

// ── Root screen ───────────────────────────────────────────────────────────────

class TimetableScreen extends StatefulWidget {
  final WebUntisService service;
  const TimetableScreen({super.key, required this.service});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  // PageView uses a virtual index; _kBase is page 0 in week-offset space.
  static const int _kBase = 500;

  late final PageController _pageController;

  // offset → _WeekData cache
  final Map<int, _WeekData> _cache = {};

  // The current week offset (0 = this week)
  int _currentOffset = 0;

  // Which day tab is selected (-1 = none)
  int _selectedDay = -1;

  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  static const _months = [
    'Jan',
    'Feb',
    'Mär',
    'Apr',
    'Mai',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Okt',
    'Nov',
    'Dez',
  ];

  static const _fixedBreakWindows = [
    (start: 1020, end: 1030),
    (start: 1455, end: 1505),
  ];

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
    _selectedDay = (now.weekday <= 5) ? now.weekday - 1 : -1;

    _pageController = PageController(initialPage: _kBase);

    // Pre-load current + neighbours
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
    // Strip time → pure date, avoids day-bleeding around midnight
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    return thisMonday.add(Duration(days: offset * 7));
  }

  bool _isThisWeek(int offset) => offset == 0;

  bool _isToday(int offset, int dayIndex) {
    final date = _mondayForOffset(offset).add(Duration(days: dayIndex));
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
      final entries = await widget.service.getWeekTimetable(
        weekStart: weekStart,
      );
      if (!mounted) return;
      setState(() {
        _cache[offset] = _WeekData(state: _LoadState.done, entries: entries);
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
        _cache[offset] = _WeekData(state: _LoadState.error, error: '$e');
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
      // Highlight today only on the current week — nowhere else
      _selectedDay = (offset == 0 && now.weekday <= 5) ? now.weekday - 1 : -1;
    });
    // Pre-load neighbours
    _ensureLoaded(offset - 1);
    _ensureLoaded(offset);
    _ensureLoaded(offset + 1);
    // Evict far-away pages to save memory (keep ±3)
    _cache.removeWhere((k, _) => (k - offset).abs() > 3);
  }

  void _goToToday() {
    final now = DateTime.now();
    setState(() => _selectedDay = (now.weekday <= 5) ? now.weekday - 1 : -1);
    final targetPage = _kBase; // offset 0 = this week
    _pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOutCubic,
    );
  }

  // ── Entry helpers ──────────────────────────────────────────────────────────

  List<TimetableEntry> _forDay(int offset, int dayIndex) {
    final date = _mondayForOffset(offset).add(Duration(days: dayIndex));
    final dateInt = int.parse(
      '${date.year}${date.month.toString().padLeft(2, '0')}${date.day.toString().padLeft(2, '0')}',
    );
    final entries = _cache[offset]?.entries ?? [];
    return entries.where((e) => e.date == dateInt).toList();
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

  // ── Time maths ─────────────────────────────────────────────────────────────

  int _toMins(int packed) => (packed ~/ 100) * 60 + (packed % 100);
  int _addMinutes(int packed, int minutes) {
    final total = _toMins(packed) + minutes;
    return (total ~/ 60) * 100 + (total % 60);
  }

  bool _crossesFixedBreak(int endTime, int nextStart) {
    final endM = _toMins(endTime);
    final startM = _toMins(nextStart);
    for (final b in _fixedBreakWindows) {
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

  _SlotInfo _buildSlot(int offset, int dayIndex, int startTime, DateTime now) {
    final dayEntries = _forDay(
      offset,
      dayIndex,
    ).where((e) => e.startTime == startTime).toList();
    if (dayEntries.isEmpty) return const _SlotInfo();

    final cancelled = dayEntries.where((e) => e.isCancelled).toList();
    final active = dayEntries.where((e) => !e.isCancelled).toList();

    TimetableEntry display;
    TimetableEntry? repl;
    _SlotKind kind;

    if (cancelled.isNotEmpty && active.isNotEmpty) {
      display = cancelled.first;
      repl = active.first;
      kind = _SlotKind.replacement;
    } else if (cancelled.isNotEmpty) {
      display = cancelled.first;
      repl = null;
      kind = _SlotKind.cancelled;
    } else {
      display = active.first;
      repl = null;
      if (display.isExam) {
        kind = _SlotKind.exam;
      } else if (display.subjectName.isEmpty && display.lessonText.isNotEmpty) {
        kind = _SlotKind.event;
      } else {
        kind = _SlotKind.normal;
      }
    }

    final isNow = _isToday(offset, dayIndex) && _isCurrentLesson(display, now);
    return _SlotInfo(
      display: display,
      replacement: repl,
      isNow: isNow,
      kind: kind,
    );
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

  void _showDetail(TimetableEntry entry, TimetableEntry? replacement) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _DetailSheet(
        entry: entry,
        replacement: replacement,
        service: widget.service,
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
              const Text(
                'Stundenplan',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              if (!_isThisWeek(_currentOffset)) ...[
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _goToToday,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Heute',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WeekNavButton(
                icon: CupertinoIcons.chevron_left,
                onTap: () => _pageController.previousPage(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${weekStart.day}. ${_months[weekStart.month - 1]} – '
                  '${weekEnd.day}. ${_months[weekEnd.month - 1]} ${weekEnd.year}',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Text(
                'KW ${_weekNumber(weekStart)}',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textTertiary,
                ),
              ),
              const SizedBox(width: 10),
              _WeekNavButton(
                icon: CupertinoIcons.chevron_right,
                onTap: () => _pageController.nextPage(
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeInOutCubic,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Week Page (one page in the PageView) ──────────────────────────────────────

class _WeekPage extends StatelessWidget {
  final int offset;
  final _TimetableScreenState state;

  const _WeekPage({super.key, required this.offset, required this.state});

  @override
  Widget build(BuildContext context) {
    final data = state._cache[offset];
    final loadState = data?.state ?? _LoadState.loading;

    if (loadState == _LoadState.loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CupertinoActivityIndicator(radius: 14),
            SizedBox(height: 14),
            Text(
              'Stundenplan wird geladen…',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
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
                style: const TextStyle(color: AppTheme.textSecondary),
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
                  style: TextStyle(fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (state._isHolidayWeek(offset)) {
      return _buildHolidayWeek();
    }

    return _buildWeekGrid();
  }

  Widget _buildHolidayWeek() {
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
          const Text(
            'Ferien',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.w700,
              color: AppTheme.textPrimary,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'In dieser Woche ist kein Unterricht.',
            style: TextStyle(fontSize: 15, color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 4),
          Text(
            'KW ${state._weekNumber(state._mondayForOffset(offset))} · Genieße die Zeit! ☀️',
            style: const TextStyle(fontSize: 13, color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekGrid() {
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
      if (timeConnected[i]) return _TimetableScreenState._connectedGap;
      if (lunchGapIndex != null && i == lunchGapIndex) {
        return _TimetableScreenState._lunchGap;
      }
      final endT =
          endTimeForStart[sortedTimes[i]] ??
          state._addMinutes(sortedTimes[i], 50);
      if (state._crossesFixedBreak(endT, sortedTimes[i + 1])) {
        return _TimetableScreenState._breakGap;
      }
      return _TimetableScreenState._normalGap;
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
                final date = state
                    ._mondayForOffset(offset)
                    .add(Duration(days: i));
                final isToday = state._isToday(offset, i);

                final isHoliday = state._isSingleHolidayDay(offset, i);
                return Expanded(
                  child: GestureDetector(
                    onTap: () => state.setState(() => state._selectedDay = i),
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
                            _TimetableScreenState._dayLabels[i],
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isToday
                                  ? AppTheme.accent
                                  : isHoliday
                                  ? AppTheme.orange.withValues(alpha: 0.8)
                                  : AppTheme.textTertiary,
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
                                      : isHoliday
                                      ? AppTheme.orange
                                      : AppTheme.textPrimary,
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
        Container(height: 0.5, color: AppTheme.border.withValues(alpha: 0.3)),
        Expanded(
          child: RefreshIndicator(
            color: AppTheme.accent,
            backgroundColor: AppTheme.surface,
            onRefresh: () async {
              state._retryOffset(offset);
              // wait for done
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

    return Row(
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
                  height: _TimetableScreenState._rowMinHeight,
                ),
                if (i < n - 1) SizedBox(height: gapAfter(i)),
              ],
            ],
          ),
        ),
        // Day columns
        ...List.generate(5, (dayIndex) {
          final isHoliday = state._isSingleHolidayDay(offset, dayIndex);

          if (isHoliday) {
            final totalHeight =
                n * _TimetableScreenState._rowMinHeight +
                List.generate(
                  n - 1,
                  (i) => gapAfter(i),
                ).fold(0.0, (a, b) => a + b);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: _HolidayColumn(totalHeight: totalHeight),
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
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDayColumn({
    required int dayIndex,
    required List<int> sortedTimes,
    required List<bool> timeConnected,
    required double Function(int) gapAfter,
    required DateTime now,
  }) {
    final n = sortedTimes.length;
    final slots = List<_SlotInfo>.generate(
      n,
      (idx) => state._buildSlot(offset, dayIndex, sortedTimes[idx], now),
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
          groupLen * _TimetableScreenState._rowMinHeight +
          (groupLen - 1) * _TimetableScreenState._connectedGap;

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
            onTap: (slot) {
              if (slot.display != null) {
                state._showDetail(slot.display!, slot.replacement);
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

// ── Merged Cell ───────────────────────────────────────────────────────────────

class _MergedCell extends StatelessWidget {
  final List<_SlotInfo> slots;
  final double height;
  final void Function(_SlotInfo slot) onTap;
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
    final isNow = slots.any((s) => s.isNow);

    final isTappable = slots.any((s) {
      if (s.isEmpty) return false;
      final e = s.display!;
      return e.isCancelled ||
          e.isExam ||
          e.lessonText.isNotEmpty ||
          s.replacement != null;
    });

    return GestureDetector(
      onTap: isTappable ? () => onTap(primary) : null,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(6),
          border: isNow
              ? Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.7),
                  width: 1.5,
                )
              : entry.isExam
              ? Border.all(
                  color: AppTheme.warning.withValues(alpha: 0.5),
                  width: 1.0,
                )
              : Border.all(color: AppTheme.border.withValues(alpha: 0.15)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(5),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 3,
                color: entry.isCancelled
                    ? AppTheme.danger.withValues(alpha: 0.4)
                    : entry.isExam
                    ? AppTheme.warning.withValues(alpha: 0.8)
                    : subjectColor.withValues(alpha: 0.55),
              ),
              Expanded(
                child: _SlotContent(slot: primary, isTappable: isTappable),
              ),
            ],
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

    IconData? statusIcon;
    Color? statusIconColor;
    if (entry.isCancelled && !hasReplacement) {
      statusIcon = CupertinoIcons.xmark_circle_fill;
      statusIconColor = AppTheme.danger;
    } else if (entry.isExam) {
      statusIcon = CupertinoIcons.doc_text_fill;
      statusIconColor = AppTheme.warning;
    } else if (hasReplacement) {
      statusIcon = CupertinoIcons.arrow_right_arrow_left;
      statusIconColor = AppTheme.colorForSubject(replacement.subjectName);
    } else if (entry.lessonText.isNotEmpty) {
      statusIcon = CupertinoIcons.doc_plaintext;
      statusIconColor = AppTheme.tint;
    }

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
                Text(
                  entry.subjectName.isNotEmpty
                      ? entry.subjectName
                      : entry.lessonText,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
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
                if (entry.teacherName.isNotEmpty) ...[
                  const SizedBox(height: 0),
                  Text(
                    entry.teacherName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                if (entry.roomName.isNotEmpty) ...[
                  const SizedBox(height: 0),
                  Text(
                    entry.roomName,
                    style: const TextStyle(
                      fontSize: 10,
                      color: AppTheme.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
            if (statusIcon != null)
              Positioned(
                right: 0,
                bottom: 0,
                child: Icon(statusIcon, size: 11, color: statusIconColor),
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
  const _DetailSheet({
    required this.entry,
    required this.replacement,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final color = entry.isCancelled
        ? AppTheme.danger
        : entry.isExam
        ? AppTheme.warning
        : AppTheme.colorForSubject(entry.subjectName);
    final lessonNr = service.getLessonNumber(entry.startTime);

    return Container(
      decoration: const BoxDecoration(
        color: AppTheme.surface,
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
                color: AppTheme.border,
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
                    lessonNr ??
                        (entry.subjectName.isNotEmpty
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
                      entry.displayName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (entry.subjectName.isNotEmpty &&
                        entry.subjectLong.isNotEmpty &&
                        entry.subjectName != entry.subjectLong)
                      Text(
                        entry.subjectLong,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppTheme.textSecondary,
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
                ),
            ],
          ),
          const SizedBox(height: 20),
          Container(height: 0.5, color: AppTheme.border.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          _InfoRow(
            icon: CupertinoIcons.clock,
            label: 'Zeit',
            value:
                '${entry.startFormatted} – ${entry.endFormatted}'
                '${lessonNr != null ? '  ·  $lessonNr. Stunde' : ''}',
          ),
          if (entry.teacherName.isNotEmpty) ...[
            const SizedBox(height: 10),
            _InfoRow(
              icon: CupertinoIcons.person,
              label: 'Lehrer',
              value: entry.teacherName,
            ),
          ],
          if (entry.roomName.isNotEmpty) ...[
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
              color: AppTheme.border.withValues(alpha: 0.4),
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
                const Text(
                  'Notiz',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.card,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                entry.lessonText,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppTheme.textPrimary,
                  height: 1.4,
                ),
              ),
            ),
          ],
          if (replacement != null) ...[
            const SizedBox(height: 16),
            Container(
              height: 0.5,
              color: AppTheme.border.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Icon(
                  CupertinoIcons.arrow_right_arrow_left,
                  size: 14,
                  color: AppTheme.colorForSubject(replacement!.subjectName),
                ),
                const SizedBox(width: 6),
                const Text(
                  'Ersatz / Vertretung',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.card,
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
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
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
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
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    this.small = false,
  });
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: small ? 12 : 14, color: AppTheme.textTertiary),
      const SizedBox(width: 8),
      Text(
        '$label  ',
        style: TextStyle(
          fontSize: small ? 12 : 13,
          color: AppTheme.textTertiary,
        ),
      ),
      Expanded(
        child: Text(
          value,
          style: TextStyle(
            fontSize: small ? 12 : 13,
            fontWeight: FontWeight.w500,
            color: AppTheme.textSecondary,
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
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textTertiary,
                ),
              ),
            Text(
              '$h:$m',
              style: const TextStyle(
                fontSize: 10,
                color: AppTheme.textTertiary,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeekNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _WeekNavButton({required this.icon, required this.onTap});
  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 15, color: AppTheme.textSecondary),
    ),
  );
}
