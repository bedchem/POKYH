import 'dart:io';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/auth_service.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import '../widgets/top_bar_actions.dart';
import 'login_screen.dart';

// ── Format helpers ────────────────────────────────────────────────────────────

String _fmtExact(int m) {
  final h = m ~/ 60;
  final rem = m % 60;
  return rem == 0 ? '${h}h' : '${h}h ${rem}m';
}

String _fmtRounded(int m) => '${(m / 60).round()}h';

String _fmt(int m, {required bool exact}) => exact ? _fmtExact(m) : _fmtRounded(m);

class AbsencesScreen extends StatefulWidget {
  final WebUntisService service;
  const AbsencesScreen({super.key, required this.service});

  @override
  State<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends State<AbsencesScreen> {
  List<AbsenceEntry> _absences = [];
  int? _totalPossibleMins;
  bool _loading = true;
  String? _error;
  bool _exact = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    if (!AuthService.instance.isUntisUser) {
      if (mounted) setState(() { _loading = false; _error = null; });
      return;
    }
    final cached = widget.service.cachedAbsences;
    if (cached != null && !forceRefresh) {
      setState(() {
        _absences = cached;
        _loading = false;
        _error = null;
      });
      if (_totalPossibleMins == null) _loadPossibleMins();
      _refreshInBackground();
      return;
    }
    setState(() {
      _loading = _absences.isEmpty;
      _error = null;
    });
    try {
      final absences = await widget.service.getAbsences(forceRefresh: forceRefresh);
      if (mounted) setState(() { _absences = absences; _loading = false; });
      _loadPossibleMins();
    } on WebUntisException catch (e) {
      if (!mounted) return;
      if (e.isAuthError) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const LoginScreen()),
        );
        return;
      }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = simplifyErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _refreshInBackground() async {
    if (!AuthService.instance.isUntisUser) return;
    try {
      final absences = await widget.service.getAbsences(forceRefresh: true);
      if (mounted) setState(() => _absences = absences);
      _loadPossibleMins();
    } catch (_) {}
  }

  List<DateTime> _schoolYearWeeks() {
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    var d = DateTime(startYear, 9, 1);
    while (d.weekday != DateTime.monday) d = d.subtract(const Duration(days: 1));
    final weeks = <DateTime>[];
    while (!d.isAfter(now)) {
      weeks.add(d);
      d = d.add(const Duration(days: 7));
    }
    return weeks;
  }

  Future<void> _loadPossibleMins() async {
    try {
      final now = DateTime.now();
      final startYear = now.month >= 9 ? now.year : now.year - 1;
      final sepNum = startYear * 10000 + 9 * 100 + 1;
      final nowNum = now.year * 10000 + now.month * 100 + now.day;

      final weeks = _schoolYearWeeks();
      final results = await Future.wait(
        weeks.map((w) => widget.service
            .getWeekSlotsForAbsences(w)
            .catchError((_) => <int, List<(int, int)>>{})),
      );

      var possible = 0;
      for (final weekMap in results) {
        for (final e in weekMap.entries) {
          if (e.key >= sepNum && e.key <= nowNum) {
            for (final slot in e.value) {
              possible += slot.$2 - slot.$1;
            }
          }
        }
      }

      if (mounted) {
        setState(() => _totalPossibleMins = possible > 0 ? possible : null);
      }
    } catch (_) {}
  }

  // ── Totals ────────────────────────────────────────────────────────────────

  int _mins(AbsenceEntry a) => a.calculatedMinutes ?? (a.hours * 60);

  int get _totalMinutes => _absences.fold(0, (s, a) => s + _mins(a));
  int get _excusedMinutes =>
      _absences.where((a) => a.isExcused).fold(0, (s, a) => s + _mins(a));
  int get _unexcusedMinutes => _totalMinutes - _excusedMinutes;

  double get _absenceRate {
    final possible = _totalPossibleMins;
    if (possible == null || possible <= 0) return 0.0;
    return (_totalMinutes / possible * 100).clamp(0.0, 100.0);
  }

  Map<String, List<AbsenceEntry>> get _grouped {
    final result = <String, List<AbsenceEntry>>{};
    for (final a in _absences) {
      final dt = a.startDateTime;
      result
          .putIfAbsent('${AppConfig.monthLabels[dt.month - 1]} ${dt.year}', () => [])
          .add(a);
    }
    return result;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isUntisUser = AuthService.instance.isUntisUser;
    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Sticky Header ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: context.appSurface,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: context.appBorder.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Icon(
                        Platform.isIOS
                            ? CupertinoIcons.chevron_left
                            : Icons.arrow_back,
                        size: 16,
                        color: AppTheme.accent,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      'Abwesenheiten',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                        letterSpacing: -0.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 10),
                  TopBarActions(service: widget.service),
                ],
              ),
            ),

            if (!isUntisUser)
              Expanded(
                child: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          CupertinoIcons.person_crop_circle_badge_exclam,
                          size: 56,
                          color: context.appTextTertiary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'Kein Schulkonto verknüpft',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Abwesenheiten sind nur mit einem WebUntis-Konto verfügbar.',
                          style: TextStyle(fontSize: 14, color: context.appTextSecondary),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              )
            else

            // ── Scrollable Body ────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                onRefresh: () => _load(forceRefresh: true),
                color: AppTheme.accent,
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // ── Overview Card ────────────────────────────────────
                    if (!_loading && _error == null)
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                          child: _OverviewCard(
                            totalMinutes: _totalMinutes,
                            excusedMinutes: _excusedMinutes,
                            unexcusedMinutes: _unexcusedMinutes,
                            absenceRate: _absenceRate,
                            exact: _exact,
                            onToggle: () => setState(() => _exact = !_exact),
                          ),
                        ),
                      ),

                    const SliverToBoxAdapter(child: SizedBox(height: 10)),

                    // ── Content ──────────────────────────────────────────
                    if (_loading)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const CupertinoActivityIndicator(radius: 14),
                              const SizedBox(height: 14),
                              Text(
                                'Abwesenheiten werden geladen…',
                                style: TextStyle(
                                  color: context.appTextSecondary,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_error != null)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 40),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 56,
                                  height: 56,
                                  decoration: BoxDecoration(
                                    color: AppTheme.danger.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(
                                    CupertinoIcons.exclamationmark_triangle_fill,
                                    color: AppTheme.danger,
                                    size: 24,
                                  ),
                                ),
                                const SizedBox(height: 14),
                                Text(
                                  _error!,
                                  style: TextStyle(
                                    color: context.appTextSecondary,
                                    fontSize: 14,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 18),
                                GestureDetector(
                                  onTap: _load,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 24,
                                      vertical: 12,
                                    ),
                                    decoration: BoxDecoration(
                                      color: AppTheme.accent,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: const Text(
                                      'Erneut versuchen',
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      )
                    else if (_absences.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 64,
                                height: 64,
                                decoration: BoxDecoration(
                                  color: AppTheme.tint.withValues(alpha: 0.1),
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  CupertinoIcons.checkmark_seal_fill,
                                  size: 28,
                                  color: AppTheme.tint,
                                ),
                              ),
                              const SizedBox(height: 14),
                              Text(
                                'Keine Abwesenheiten',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  color: context.appTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Du hattest in diesem Schuljahr keine\neingetragenen Abwesenheiten.',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: context.appTextSecondary,
                                  height: 1.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      SliverPadding(
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 40),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (_, i) {
                              final months = _grouped.keys.toList();
                              final entries = _grouped[months[i]]!;
                              return _MonthSection(
                                month: months[i],
                                entries: entries,
                                exact: _exact,
                              );
                            },
                            childCount: _grouped.length,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Overview Card ─────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final int totalMinutes;
  final int excusedMinutes;
  final int unexcusedMinutes;
  final double absenceRate;
  final bool exact;
  final VoidCallback onToggle;

  const _OverviewCard({
    required this.totalMinutes,
    required this.excusedMinutes,
    required this.unexcusedMinutes,
    required this.absenceRate,
    required this.exact,
    required this.onToggle,
  });

  Color _rateColor(double rate) =>
      rate >= 15 ? AppTheme.danger : rate >= 5 ? AppTheme.warning : AppTheme.tint;

  @override
  Widget build(BuildContext context) {
    final rateFraction = (absenceRate / 100).clamp(0.0, 1.0);
    final rateColor = _rateColor(absenceRate);

    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: context.appBorder.withValues(alpha: 0.35)),
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Fehlstunden gesamt',
                      style: TextStyle(
                        fontSize: 11,
                        color: context.appTextSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmt(totalMinutes, exact: exact),
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                        letterSpacing: -1,
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: onToggle,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: exact ? AppTheme.tint : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppTheme.tint, width: 1.5),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        exact
                            ? CupertinoIcons.timer_fill
                            : CupertinoIcons.clock,
                        size: 12,
                        color: exact ? Colors.white : AppTheme.tint,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        exact ? 'Exakt' : 'Gerundet',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: exact ? Colors.white : AppTheme.tint,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _InlineStat(
                label: 'Entschuldigt',
                value: _fmt(excusedMinutes, exact: exact),
                color: AppTheme.tint,
              ),
              const Spacer(),
              _InlineStat(
                label: 'Unentschuldigt',
                value: _fmt(unexcusedMinutes, exact: exact),
                color: unexcusedMinutes > 0
                    ? AppTheme.danger
                    : context.appTextTertiary,
                alignEnd: true,
              ),
            ],
          ),

          const SizedBox(height: 16),

          Row(
            children: [
              Text(
                'Fehlquote',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: context.appTextSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${absenceRate.toStringAsFixed(1)} %',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: rateColor,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: SizedBox(
              height: 8,
              child: LayoutBuilder(
                builder: (_, constraints) {
                  final w = constraints.maxWidth;
                  final fillW = (w * rateFraction).clamp(0.0, w);
                  return Stack(
                    children: [
                      Container(width: w, color: context.appCard),
                      if (fillW > 0)
                        Container(
                          width: fillW,
                          decoration: BoxDecoration(
                            color: rateColor,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool alignEnd;
  const _InlineStat({
    required this.label,
    required this.value,
    required this.color,
    this.alignEnd = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment:
          alignEnd ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -0.5,
            height: 1.1,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: context.appTextSecondary),
        ),
      ],
    );
  }
}

// ── Month Section ─────────────────────────────────────────────────────────────

class _MonthSection extends StatelessWidget {
  final String month;
  final List<AbsenceEntry> entries;
  final bool exact;

  const _MonthSection({
    required this.month,
    required this.entries,
    required this.exact,
  });

  int _mins(AbsenceEntry a) => a.calculatedMinutes ?? (a.hours * 60);

  @override
  Widget build(BuildContext context) {
    final monthMinutes = entries.fold(0, (s, a) => s + _mins(a));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
            child: Row(
              children: [
                Text(
                  month,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: context.appSeparator.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 8),
                _MonthChip(
                  label: _fmt(monthMinutes, exact: exact),
                  color: context.appTextSecondary,
                ),
              ],
            ),
          ),
          ...entries.asMap().entries.map(
            (e) => Padding(
              padding: EdgeInsets.only(
                bottom: e.key < entries.length - 1 ? 8 : 0,
              ),
              child: _AbsenceCard(
                entry: e.value,
                minutes: _mins(e.value),
                exact: exact,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthChip extends StatelessWidget {
  final String label;
  final Color color;
  const _MonthChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }
}

// ── Absence Card ──────────────────────────────────────────────────────────────

class _AbsenceCard extends StatelessWidget {
  final AbsenceEntry entry;
  final int minutes;
  final bool exact;

  const _AbsenceCard({
    required this.entry,
    required this.minutes,
    required this.exact,
  });

  @override
  Widget build(BuildContext context) {
    final isExcused = entry.isExcused;
    final iconColor = isExcused ? AppTheme.tint : AppTheme.danger;
    final hasSecondary = entry.timeFormatted.isNotEmpty ||
        entry.subjectName != null ||
        entry.teacherName != null;

    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: context.appBorder.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.dateFormatted,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.appTextPrimary,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (hasSecondary) ...[
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (entry.timeFormatted.isNotEmpty) entry.timeFormatted,
                          if (entry.subjectName != null) entry.subjectName!,
                          if (entry.teacherName != null) entry.teacherName!,
                        ].join(' · '),
                        style: TextStyle(
                          fontSize: 12,
                          color: context.appTextSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Row(
                children: [
                  Text(
                    _fmt(minutes, exact: exact),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Icon(
                    isExcused
                        ? CupertinoIcons.checkmark_circle_fill
                        : CupertinoIcons.xmark_circle_fill,
                    size: 18,
                    color: iconColor,
                  ),
                ],
              ),
            ],
          ),

          if (entry.reasonName != null) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: context.appCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Grund',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.appTextTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.reasonName!,
                      style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (entry.note != null) ...[
            const SizedBox(height: 6),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: context.appCard,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    'Text',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: context.appTextTertiary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      entry.note!,
                      style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
