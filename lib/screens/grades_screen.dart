import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../config/app_config.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import '../widgets/top_bar_actions.dart';
import 'login_screen.dart';

// ── Sort mode ──────────────────────────────────────────────────────────────────

enum _SortMode { name, avgDesc, avgAsc, recent }

// ── Grade color helpers ────────────────────────────────────────────────────────

Color _gradeColor(double v) {
  if (v >= 6) return AppTheme.tint;
  if (v >= 5) return AppTheme.orange;
  return AppTheme.danger;
}

// Per-integer color — matches web's DONUT_GRADE_COLORS
Color _gradeColorByRank(int grade) {
  switch (grade) {
    case 10: return const Color(0xFF30D158);
    case 9:  return const Color(0xFF00C7BE);
    case 8:  return const Color(0xFF0A84FF);
    case 7:  return const Color(0xFF5E5CE6);
    case 6:  return const Color(0xFFFFD60A);
    case 5:  return const Color(0xFFFF9F0A);
    default: return const Color(0xFFFF453A); // 4 and below = red
  }
}

// Segments for donut hit-testing and painting
typedef _SegInfo = ({int grade, double start, double sweep});

List<_SegInfo> _computeDonutSegs(Map<int, int> distribution) {
  final total = distribution.values.fold(0, (a, b) => a + b);
  if (total == 0) return [];
  const gap = 0.035;
  double a = -math.pi / 2;
  final sorted = distribution.entries.toList()..sort((x, y) => y.key.compareTo(x.key));
  return sorted.map((e) {
    final sweep = ((e.value / total) * math.pi * 2 - gap).clamp(0.01, math.pi * 2);
    final seg = (grade: e.key, start: a, sweep: sweep);
    a += sweep + gap;
    return seg;
  }).toList();
}

String _fmtNum(double v, {int digits = 2}) {
  final s = v.toStringAsFixed(digits);
  return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
}

String _fmtDateShort(int date) {
  final s = date.toString();
  if (s.length != 8) return s;
  return '${s.substring(6)}.${s.substring(4, 6)}.${s.substring(2, 4)}';
}

// ── KPI data ───────────────────────────────────────────────────────────────────

class _RecentGrade {
  final String subjectName;
  final GradeEntry grade;
  const _RecentGrade({required this.subjectName, required this.grade});
}

class _KpiData {
  final double? avg;
  final double? delta;
  final double? prevAvg;
  final double bestGrade;
  final int pos;
  final int neg;
  final double passRate;
  final Map<int, int> distribution;
  final int? modeGrade;
  final double median;
  final List<double> sparkline;
  final List<String> sparklineMonths;
  final List<_RecentGrade> recent;

  const _KpiData({
    this.avg,
    this.delta,
    this.prevAvg,
    this.bestGrade = 0,
    this.pos = 0,
    this.neg = 0,
    this.passRate = 0,
    this.distribution = const {},
    this.modeGrade,
    this.median = 0,
    this.sparkline = const [],
    this.sparklineMonths = const [],
    this.recent = const [],
  });
}

// ── Main screen ────────────────────────────────────────────────────────────────

class GradesScreen extends StatefulWidget {
  final WebUntisService service;
  const GradesScreen({super.key, required this.service});

  @override
  State<GradesScreen> createState() => _GradesScreenState();
}

class _GradesScreenState extends State<GradesScreen> {
  List<SubjectGrades> _subjects = [];
  bool _loading = true;
  String? _error;
  _SortMode _sortMode = _SortMode.name;
  final Set<String> _expanded = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final cached = widget.service.cachedGrades;
    if (cached != null && !forceRefresh) {
      setState(() { _subjects = cached; _loading = false; });
      _refreshInBackground();
      return;
    }
    setState(() { _loading = _subjects.isEmpty; _error = null; });
    try {
      final grades = await widget.service.getAllGrades(forceRefresh: forceRefresh);
      if (mounted) setState(() { _subjects = grades; _loading = false; });
    } on WebUntisException catch (e) {
      if (!mounted) return;
      if (e.isAuthError) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const LoginScreen()));
        return;
      }
      setState(() { _error = e.message; _loading = false; });
    } catch (e) {
      if (mounted) setState(() { _error = simplifyErrorMessage(e); _loading = false; });
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final grades = await widget.service.getAllGrades(forceRefresh: true);
      if (mounted) setState(() => _subjects = grades);
    } catch (_) {}
  }

  List<SubjectGrades> get _sortedSubjects {
    final list = List<SubjectGrades>.from(_subjects);
    switch (_sortMode) {
      case _SortMode.name:
        list.sort((a, b) => a.subjectName.compareTo(b.subjectName));
      case _SortMode.avgDesc:
        list.sort((a, b) => (b.average ?? 0).compareTo(a.average ?? 0));
      case _SortMode.avgAsc:
        list.sort((a, b) => (a.average ?? 0).compareTo(b.average ?? 0));
      case _SortMode.recent:
        list.sort((a, b) {
          final aD = a.grades.isEmpty ? 0 : a.grades.map((g) => g.date).reduce(math.max);
          final bD = b.grades.isEmpty ? 0 : b.grades.map((g) => g.date).reduce(math.max);
          return bD.compareTo(aD);
        });
    }
    return list;
  }

  bool get _allExpanded =>
      _subjects.isNotEmpty && _expanded.length >= _sortedSubjects.length;

  void _toggleExpandAll() {
    setState(() {
      if (_allExpanded) {
        _expanded.clear();
      } else {
        for (final s in _sortedSubjects) _expanded.add(s.subjectName);
      }
    });
  }

  _KpiData _computeKpi() {
    final all = _subjects.expand((s) => s.grades).toList();
    if (all.isEmpty) return const _KpiData();
    final values = all.map((g) => g.markDisplayValue).where((v) => v > 0).toList();
    if (values.isEmpty) return const _KpiData();

    final avg = values.reduce((a, b) => a + b) / values.length;
    final bestGrade = values.reduce(math.max);

    // Delta vs grades before current month
    final now = DateTime.now();
    final currentMonthInt = now.year * 100 + now.month;
    final prevValues = all.where((g) {
      final s = g.date.toString();
      if (s.length != 8) return false;
      final ym = int.tryParse(s.substring(0, 6)) ?? 0;
      return ym < currentMonthInt;
    }).map((g) => g.markDisplayValue).where((v) => v > 0).toList();
    final prevAvg = prevValues.isEmpty
        ? null
        : prevValues.reduce((a, b) => a + b) / prevValues.length;
    final delta = prevAvg != null ? avg - prevAvg : null;

    // Pos / neg
    final pos = values.where((v) => v >= 6).length;
    final neg = values.where((v) => v < 6).length;
    final total = pos + neg;
    final passRate = total > 0 ? pos / total : 0.0;

    // Distribution by rounded grade
    final dist = <int, int>{};
    for (final v in values) {
      final k = v.round().clamp(1, 10);
      dist[k] = (dist[k] ?? 0) + 1;
    }

    // Mode
    int? modeGrade;
    int modeCount = 0;
    for (final e in dist.entries) {
      if (e.value > modeCount) { modeCount = e.value; modeGrade = e.key; }
    }

    // Median
    final sorted = List<double>.from(values)..sort();
    final double median;
    if (sorted.length % 2 == 1) {
      median = sorted[sorted.length ~/ 2];
    } else {
      final mid = sorted.length ~/ 2;
      median = (sorted[mid - 1] + sorted[mid]) / 2;
    }

    // Sparkline: cumulative average per month
    const _monthNames = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];
    final monthGroups = <String, List<double>>{};
    for (final g in all) {
      final s = g.date.toString();
      if (s.length != 8) continue;
      monthGroups.putIfAbsent(s.substring(0, 6), () => []).add(g.markDisplayValue);
    }
    final sortedMonths = monthGroups.keys.toList()..sort();
    final sparkline = <double>[];
    final sparklineMonths = <String>[];
    double runSum = 0;
    int runCount = 0;
    for (final m in sortedMonths) {
      for (final v in monthGroups[m]!) { runSum += v; runCount++; }
      sparkline.add(runSum / runCount);
      final monthIdx = (int.tryParse(m.substring(4, 6)) ?? 1).clamp(1, 12) - 1;
      sparklineMonths.add('${_monthNames[monthIdx]} ${m.substring(2, 4)}');
    }

    // Recently added (last 3 by lastUpdate / date)
    final recentAll = _subjects
        .expand((s) => s.grades.map((g) => _RecentGrade(subjectName: s.subjectName, grade: g)))
        .toList();
    recentAll.sort((a, b) {
      final au = a.grade.lastUpdate > 0 ? a.grade.lastUpdate : a.grade.date;
      final bu = b.grade.lastUpdate > 0 ? b.grade.lastUpdate : b.grade.date;
      return bu.compareTo(au);
    });
    final recent = recentAll.take(3).toList();

    return _KpiData(
      avg: avg, delta: delta, prevAvg: prevAvg, bestGrade: bestGrade,
      pos: pos, neg: neg, passRate: passRate,
      distribution: dist, modeGrade: modeGrade, median: median,
      sparkline: sparkline, sparklineMonths: sparklineMonths, recent: recent,
    );
  }

  String get _sortLabel {
    switch (_sortMode) {
      case _SortMode.name:    return 'Name';
      case _SortMode.avgDesc: return 'Bester ⌀';
      case _SortMode.avgAsc:  return 'Schlechtester ⌀';
      case _SortMode.recent:  return 'Letzte Note';
    }
  }

  void _showSortSheet(BuildContext context) {
    if (Platform.isIOS) {
      showCupertinoModalPopup(
        context: context,
        builder: (_) => CupertinoActionSheet(
          title: const Text('Sortieren nach'),
          actions: [
            _sortActionCupertino(context, 'Name', _SortMode.name),
            _sortActionCupertino(context, 'Bester ⌀', _SortMode.avgDesc),
            _sortActionCupertino(context, 'Schlechtester ⌀', _SortMode.avgAsc),
            _sortActionCupertino(context, 'Letzte Note', _SortMode.recent),
          ],
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(context),
            child: const Text('Abbrechen'),
          ),
        ),
      );
    } else {
      showModalBottomSheet(
        context: context,
        backgroundColor: context.appSurface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        builder: (_) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Text('Sortieren nach',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
              ),
              _sortActionMaterial(context, 'Name', _SortMode.name),
              _sortActionMaterial(context, 'Bester ⌀', _SortMode.avgDesc),
              _sortActionMaterial(context, 'Schlechtester ⌀', _SortMode.avgAsc),
              _sortActionMaterial(context, 'Letzte Note', _SortMode.recent),
              const SizedBox(height: 8),
            ],
          ),
        ),
      );
    }
  }

  Widget _sortActionCupertino(BuildContext ctx, String label, _SortMode mode) =>
      CupertinoActionSheetAction(
        isDefaultAction: _sortMode == mode,
        onPressed: () { setState(() => _sortMode = mode); Navigator.pop(ctx); },
        child: Text(label),
      );

  Widget _sortActionMaterial(BuildContext ctx, String label, _SortMode mode) {
    final selected = _sortMode == mode;
    return ListTile(
      title: Text(label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            color: selected ? AppTheme.accent : ctx.appTextPrimary,
          )),
      trailing: selected ? Icon(Icons.check, color: AppTheme.accent, size: 20) : null,
      onTap: () { setState(() => _sortMode = mode); Navigator.pop(ctx); },
    );
  }

  @override
  Widget build(BuildContext context) {
    final kpi = _subjects.isEmpty ? const _KpiData() : _computeKpi();
    final sorted = _sortedSubjects;

    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              width: 34, height: 34,
                              decoration: BoxDecoration(
                                color: context.appSurface,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Platform.isIOS ? CupertinoIcons.chevron_left : Icons.arrow_back,
                                size: 16, color: AppTheme.accent,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            'Noten',
                            style: TextStyle(
                              fontSize: 28, fontWeight: FontWeight.w700,
                              color: context.appTextPrimary, letterSpacing: -0.5,
                            ),
                          ),
                          const Spacer(),
                          TopBarActions(service: widget.service),
                        ],
                      ),
                      if (!_loading && _error == null && _subjects.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 46),
                          child: Text(
                            '${_subjects.length} Fächer · Schuljahr ${AppConfig.currentSchoolYear}',
                            style: TextStyle(fontSize: 14, color: context.appTextSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── States ──
              if (_loading)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const CupertinoActivityIndicator(radius: 14),
                        const SizedBox(height: 14),
                        Text('Noten werden geladen…',
                            style: TextStyle(color: context.appTextSecondary, fontSize: 14)),
                      ],
                    ),
                  ),
                )
              else if (_error != null)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 56, height: 56,
                          decoration: BoxDecoration(
                            color: AppTheme.danger.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(child: Icon(
                            CupertinoIcons.exclamationmark_triangle_fill,
                            color: AppTheme.danger, size: 24,
                          )),
                        ),
                        const SizedBox(height: 14),
                        Text(_error!, textAlign: TextAlign.center,
                            style: TextStyle(color: context.appTextSecondary)),
                        const SizedBox(height: 18),
                        CupertinoButton(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                          color: AppTheme.accent,
                          borderRadius: BorderRadius.circular(9),
                          minimumSize: Size.zero,
                          onPressed: _load,
                          child: const Text('Erneut versuchen',
                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white)),
                        ),
                      ],
                    ),
                  ),
                )
              else if (_subjects.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Text('Keine Noten vorhanden',
                        style: TextStyle(color: context.appTextSecondary, fontSize: 15)),
                  ),
                )
              else ...[
                // ── KPI Dashboard ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                    child: Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _KpiCardDurchschnitt(kpi: kpi)),
                              const SizedBox(width: 8),
                              Expanded(child: _KpiCardVerhaeltnis(kpi: kpi)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _KpiCardVerteilung(kpi: kpi)),
                              const SizedBox(width: 8),
                              Expanded(child: _KpiCardKuerzlich(kpi: kpi)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Sort bar ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        Text(
                          '${sorted.length} Fächer',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.appTextSecondary),
                        ),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => _showSortSheet(context),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.appSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.appBorder),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(CupertinoIcons.sort_down, size: 13, color: context.appTextSecondary),
                                const SizedBox(width: 5),
                                Text(_sortLabel, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.appTextSecondary)),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        GestureDetector(
                          onTap: _toggleExpandAll,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: context.appSurface,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: context.appBorder),
                            ),
                            child: Text(
                              _allExpanded ? 'Einklappen' : 'Alle aufklappen',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: context.appTextSecondary),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // ── Subject list ──
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final s = sorted[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _SubjectRow(
                            subject: s,
                            expanded: _expanded.contains(s.subjectName),
                            onToggle: () => setState(() {
                              if (_expanded.contains(s.subjectName)) {
                                _expanded.remove(s.subjectName);
                              } else {
                                _expanded.add(s.subjectName);
                              }
                            }),
                          ),
                        );
                      },
                      childCount: sorted.length,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// KPI cards
// ═══════════════════════════════════════════════════════════════════════════════

class _KpiCardDurchschnitt extends StatelessWidget {
  final _KpiData kpi;
  const _KpiCardDurchschnitt({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final avg = kpi.avg;
    final color = avg != null ? _gradeColor(avg) : context.appTextSecondary;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Durchschnittsnote',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          Text('Alle Fächer',
              style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
          const SizedBox(height: 6),
          Text(
            avg != null ? _fmtNum(avg) : '—',
            style: TextStyle(
              fontSize: 40, fontWeight: FontWeight.w700, color: color, height: 1.0,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (kpi.prevAvg != null) ...[
                Text('Vormonat ', style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
                Text(_fmtNum(kpi.prevAvg!),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                        color: context.appTextSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
              if (kpi.prevAvg != null && kpi.bestGrade > 0)
                Text('  ·  ', style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
              if (kpi.bestGrade > 0) ...[
                Text('Beste ', style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
                Text(_fmtNum(kpi.bestGrade),
                    style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                        color: context.appTextSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()])),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCardVerhaeltnis extends StatelessWidget {
  final _KpiData kpi;
  const _KpiCardVerhaeltnis({required this.kpi});

  @override
  Widget build(BuildContext context) {
    final total = kpi.pos + kpi.neg;
    final posRatio = total > 0 ? kpi.pos / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notenverhältnis',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          Text('Genügend · Ungenügend',
              style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${kpi.pos}',
                  style: const TextStyle(
                    fontSize: 32, fontWeight: FontWeight.w600, color: AppTheme.tint,
                    fontFeatures: [FontFeature.tabularFigures()], height: 1.0,
                  )),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Text('/',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w300,
                        color: context.appTextTertiary, height: 1.0)),
              ),
              Text('${kpi.neg}',
                  style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w600, color: AppTheme.danger,
                    fontFeatures: [FontFeature.tabularFigures()], height: 1.0,
                  )),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: SizedBox(
              height: 4,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(width: c.maxWidth, height: 4, color: AppTheme.danger.withValues(alpha: 0.2)),
                    Container(width: c.maxWidth * posRatio, height: 4, color: AppTheme.tint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Text('${kpi.pos}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: AppTheme.tint, fontFeatures: [FontFeature.tabularFigures()])),
              Text(' über 6.0  ·  ',
                  style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
              Text('${kpi.neg}',
                  style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                      color: AppTheme.danger, fontFeatures: [FontFeature.tabularFigures()])),
              Text(' unter 6.0',
                  style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
            ],
          ),
        ],
      ),
    );
  }
}

class _KpiCardVerteilung extends StatefulWidget {
  final _KpiData kpi;
  const _KpiCardVerteilung({required this.kpi});

  @override
  State<_KpiCardVerteilung> createState() => _KpiCardVerteilungState();
}

class _KpiCardVerteilungState extends State<_KpiCardVerteilung> {
  int? _tappedGrade;

  static const double _donutSize = 84;
  static const double _arcRadius = 25.0; // availR(31) - sw/2(6)
  static const double _sw = 12.0;

  void _onTap(TapDownDetails d) {
    const center = Offset(_donutSize / 2, _donutSize / 2);
    final pos = d.localPosition - center;
    final dist = pos.distance;
    if (dist < _arcRadius - _sw / 2 - 6 || dist > _arcRadius + _sw / 2 + 6) {
      setState(() => _tappedGrade = null);
      return;
    }
    final segs = _computeDonutSegs(widget.kpi.distribution);
    var angle = math.atan2(pos.dy, pos.dx);
    if (angle < -math.pi / 2) angle += 2 * math.pi;
    for (final seg in segs) {
      if (angle >= seg.start && angle < seg.start + seg.sweep) {
        setState(() => _tappedGrade = _tappedGrade == seg.grade ? null : seg.grade);
        return;
      }
    }
    setState(() => _tappedGrade = null);
  }

  @override
  Widget build(BuildContext context) {
    final tapped = _tappedGrade;
    final count = tapped != null ? (widget.kpi.distribution[tapped] ?? 0) : 0;

    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notenverteilung',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 6),
          Center(
            child: GestureDetector(
              onTapDown: _onTap,
              child: SizedBox(
                width: _donutSize, height: _donutSize,
                child: CustomPaint(
                  painter: _DonutPainter(
                    distribution: widget.kpi.distribution,
                    tappedGrade: _tappedGrade,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          if (tapped != null)
            Text('Note $tapped: ${count}×',
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600,
                    color: _gradeColorByRank(tapped)))
          else ...[
            if (widget.kpi.modeGrade != null)
              Text('Häufigste: ${widget.kpi.modeGrade}',
                  style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
            Text('Median: ${_fmtNum(widget.kpi.median, digits: 1)}',
                style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
          ],
        ],
      ),
    );
  }
}

class _KpiCardKuerzlich extends StatelessWidget {
  final _KpiData kpi;
  const _KpiCardKuerzlich({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kürzlich',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 6),
          if (kpi.recent.isEmpty)
            Text('—', style: TextStyle(fontSize: 13, color: context.appTextTertiary))
          else
            ...kpi.recent.map((r) {
              final gc = _gradeColor(r.grade.markDisplayValue);
              final desc = r.grade.text.isNotEmpty
                  ? r.grade.text
                  : r.grade.examType.isNotEmpty
                  ? r.grade.examType
                  : '—';
              return Padding(
                padding: const EdgeInsets.only(bottom: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.subjectName,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: context.appTextPrimary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          Text(desc,
                              style: TextStyle(fontSize: 9, color: context.appTextTertiary),
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                      decoration: BoxDecoration(
                        color: gc.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(r.grade.markName,
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: gc,
                              fontFeatures: const [FontFeature.tabularFigures()])),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}

// ── Sparkline ──────────────────────────────────────────────────────────────────

class _SparklinePainter extends CustomPainter {
  final List<double> data;
  final List<String> months;
  final Color color;
  final int? tappedIndex;
  const _SparklinePainter({
    required this.data,
    required this.months,
    required this.color,
    this.tappedIndex,
  });

  static const double _top = 18.0; // reserved for floating tooltip

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs();

    double yOf(double v) => range < 0.001
        ? (size.height + _top) / 2
        : size.height - (v - minV) / range * (size.height - _top - 3) - 2;

    // Area fill
    final areaPath = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      if (i == 0) areaPath.moveTo(x, yOf(data[i]));
      else areaPath.lineTo(x, yOf(data[i]));
    }
    areaPath.lineTo(size.width, size.height);
    areaPath.lineTo(0, size.height);
    areaPath.close();
    canvas.drawPath(
      areaPath,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.0)],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill,
    );

    // Line
    final linePaint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final path = Path();
    for (int i = 0; i < data.length; i++) {
      final x = i / (data.length - 1) * size.width;
      final y = yOf(data[i]);
      if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
    }
    canvas.drawPath(path, linePaint);

    // End dot
    canvas.drawCircle(Offset(size.width, yOf(data.last)), 2.5, Paint()..color = color);

    // Tapped state
    if (tappedIndex != null && tappedIndex! < data.length) {
      final tx = tappedIndex! / (data.length - 1) * size.width;
      final ty = yOf(data[tappedIndex!]);

      // Cursor line
      canvas.drawLine(
        Offset(tx, _top),
        Offset(tx, size.height),
        Paint()..color = color.withValues(alpha: 0.22)..strokeWidth = 1.0,
      );

      // Dot
      canvas.drawCircle(Offset(tx, ty), 3.5, Paint()..color = color);

      // Floating tooltip drawn at top of painter
      if (tappedIndex! < months.length) {
        final label = '${months[tappedIndex!]}   ${_fmtNum(data[tappedIndex!])}';
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w600, color: color),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        const hPad = 5.0, vPad = 2.5;
        var lx = tx - tp.width / 2 - hPad;
        lx = lx.clamp(0.0, size.width - tp.width - hPad * 2);
        const ly = 0.0;
        canvas.drawRRect(
          RRect.fromLTRBR(lx, ly, lx + tp.width + hPad * 2,
              ly + tp.height + vPad * 2, const Radius.circular(5)),
          Paint()..color = color.withValues(alpha: 0.13),
        );
        tp.paint(canvas, Offset(lx + hPad, ly + vPad));
      }
    }
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.data != data || old.color != color || old.tappedIndex != tappedIndex;
}

// ── Subject row ────────────────────────────────────────────────────────────────

class _SubjectRow extends StatelessWidget {
  final SubjectGrades subject;
  final bool expanded;
  final VoidCallback onToggle;
  const _SubjectRow({required this.subject, required this.expanded, required this.onToggle});

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubjectDetailSheet(subject: subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avg = subject.average;
    final color = AppTheme.colorForSubject(subject.subjectName);
    final gc = avg != null ? _gradeColor(avg) : context.appTextTertiary;

    return GestureDetector(
      onTap: onToggle,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: expanded ? Border.all(color: color.withValues(alpha: 0.3)) : null,
        ),
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 10, height: 10,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subject.subjectName,
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
                        const SizedBox(height: 2),
                        Text(
                          '${subject.teacherName} · ${subject.grades.length} Noten',
                          style: TextStyle(fontSize: 12, color: context.appTextSecondary),
                        ),
                      ],
                    ),
                  ),
                  if (avg != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: gc.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: gc.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        avg.toStringAsFixed(1),
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: gc,
                            fontFeatures: const [FontFeature.tabularFigures()]),
                      ),
                    ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 220),
                    child: Icon(CupertinoIcons.chevron_down, size: 14, color: context.appTextTertiary),
                  ),
                ],
              ),
            ),

            // Expanded content
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 220),
              crossFadeState: expanded ? CrossFadeState.showFirst : CrossFadeState.showSecond,
              firstChild: Column(
                children: [
                  Divider(
                    color: context.appBorder.withValues(alpha: 0.5),
                    height: 1, indent: 14, endIndent: 14,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 0),
                    child: Column(
                      children: subject.grades.map((g) {
                        final vColor = _gradeColor(g.markDisplayValue);
                        final desc = g.text.isNotEmpty
                            ? g.text
                            : g.examType.isNotEmpty
                            ? g.examType
                            : '—';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 58,
                                child: Text(
                                  _fmtDateShort(g.date),
                                  style: TextStyle(fontSize: 11, color: context.appTextTertiary,
                                      fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ),
                              Expanded(
                                child: Text(desc,
                                    style: TextStyle(fontSize: 13, color: context.appTextSecondary),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                constraints: const BoxConstraints(minWidth: 36),
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: vColor.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  g.markName,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: vColor,
                                      fontFeatures: const [FontFeature.tabularFigures()]),
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
                    child: GestureDetector(
                      onTap: () => _openDetail(context),
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: context.appBorder.withValues(alpha: 0.25),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: context.appBorder),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(CupertinoIcons.chart_bar_alt_fill, size: 13, color: context.appTextSecondary),
                            const SizedBox(width: 6),
                            Text('Details öffnen',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Donut chart painter (kept)
// ═══════════════════════════════════════════════════════════════════════════════

class _DonutPainter extends CustomPainter {
  final Map<int, int> distribution;
  final int? tappedGrade;
  const _DonutPainter({required this.distribution, this.tappedGrade});

  static const double _sw = 12.0;
  static const double _labelReserve = 11.0;

  @override
  void paint(Canvas canvas, Size size) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) return;
    final availR = (math.min(size.width, size.height) / 2) - _labelReserve;
    final center = Offset(size.width / 2, size.height / 2);
    final arcRadius = availR - _sw / 2;
    const gap = 0.035;
    double startAngle = -math.pi / 2;
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final midAngles = <int, double>{};
    final sweeps = <int, double>{};

    for (final entry in sorted) {
      final sweep = ((entry.value / total) * math.pi * 2 - gap).clamp(0.01, math.pi * 2);
      final isActive = tappedGrade == null || tappedGrade == entry.key;
      final paint = Paint()
        ..color = _gradeColorByRank(entry.key).withValues(alpha: isActive ? 1.0 : 0.2)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _sw
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
        startAngle, sweep, false, paint,
      );
      midAngles[entry.key] = startAngle + sweep / 2;
      sweeps[entry.key] = sweep;
      startAngle += sweep + gap;
    }

    // Labels — only show when no grade is tapped, or only the tapped one
    for (final entry in sorted) {
      if ((sweeps[entry.key] ?? 0) < 0.20) continue;
      if (tappedGrade != null && tappedGrade != entry.key) continue;
      final midAngle = midAngles[entry.key]!;
      final color = _gradeColorByRank(entry.key);

      final tickStart = Offset(
        center.dx + (arcRadius + _sw / 2 + 1) * math.cos(midAngle),
        center.dy + (arcRadius + _sw / 2 + 1) * math.sin(midAngle),
      );
      final tickEnd = Offset(
        center.dx + (arcRadius + _sw / 2 + 5) * math.cos(midAngle),
        center.dy + (arcRadius + _sw / 2 + 5) * math.sin(midAngle),
      );
      canvas.drawLine(tickStart, tickEnd,
          Paint()..color = color.withValues(alpha: 0.8)..strokeWidth = 1.0);

      final labelR = arcRadius + _sw / 2 + _labelReserve * 0.75;
      final lx = center.dx + labelR * math.cos(midAngle);
      final ly = center.dy + labelR * math.sin(midAngle);
      final tp = TextPainter(
        text: TextSpan(
          text: '${entry.key}',
          style: TextStyle(fontSize: 8, fontWeight: FontWeight.w700, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx = (lx - tp.width / 2).clamp(0.0, size.width - tp.width);
      final ty = (ly - tp.height / 2).clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(tx, ty));
    }

    // Center count
    if (tappedGrade != null) {
      final count = distribution[tappedGrade!] ?? 0;
      final color = _gradeColorByRank(tappedGrade!);
      final tp = TextPainter(
        text: TextSpan(
          text: '${count}×',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(
        center.dx - tp.width / 2,
        center.dy - tp.height / 2,
      ));
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) =>
      old.distribution != distribution || old.tappedGrade != tappedGrade;
}

// ═══════════════════════════════════════════════════════════════════════════════
// Subject detail bottom sheet (kept)
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectDetailSheet extends StatefulWidget {
  final SubjectGrades subject;
  const _SubjectDetailSheet({required this.subject});

  @override
  State<_SubjectDetailSheet> createState() => _SubjectDetailSheetState();
}

class _SubjectDetailSheetState extends State<_SubjectDetailSheet> {
  final List<double> _extraGrades = [];
  final Set<int> _removedIds = {};
  final TextEditingController _inputCtrl = TextEditingController();
  final TextEditingController _targetCtrl = TextEditingController();
  bool _scrollResetQueued = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _targetCtrl.dispose();
    super.dispose();
  }

  List<double> get _allGradeValues => [
    ...widget.subject.grades
        .where((g) => !_removedIds.contains(g.id))
        .map((g) => g.markDisplayValue),
    ..._extraGrades,
  ];

  double? get _simAverage {
    final all = _allGradeValues;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a + b) / all.length;
  }

  Set<int> get _removedIndicesForChart {
    final result = <int>{};
    for (int i = 0; i < widget.subject.grades.length; i++) {
      if (_removedIds.contains(widget.subject.grades[i].id)) result.add(i);
    }
    return result;
  }

  bool get _hasDraft => _removedIds.isNotEmpty || _extraGrades.isNotEmpty;

  Color _gradeColor(double v) {
    if (v >= 6) return AppTheme.tint;
    if (v >= 5) return AppTheme.orange;
    return AppTheme.danger;
  }

  String _fmtGrade(double v) =>
      v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');

  String _relativeDate(int date) {
    final s = date.toString();
    if (s.length != 8) return '';
    final d = DateTime(int.parse(s.substring(0, 4)), int.parse(s.substring(4, 6)), int.parse(s.substring(6, 8)));
    final diff = DateTime.now().difference(d).inDays;
    if (diff == 0) return 'Heute';
    if (diff == 1) return 'Gestern';
    if (diff < 7) return 'vor $diff Tagen';
    if (diff < 30) return 'vor ${(diff / 7).round()} Wochen';
    if (diff < 365) return 'vor ${(diff / 30).round()} Monaten';
    return 'vor ${(diff / 365).round()} Jahren';
  }

  double _roundToStep(double v, bool up) {
    final scaled = v * 2;
    final rounded = up ? scaled.ceil() : scaled.floor();
    return (rounded / 2.0).clamp(4.0, 10.0);
  }

  ({String status, int count, double needed})? _calcRequired() {
    final text = _targetCtrl.text.replaceAll(',', '.');
    final target = double.tryParse(text);
    if (target == null || target < 1 || target > 10) return null;
    final allVals = _allGradeValues;
    final n = allVals.length;
    if (n == 0) return null;
    final sum = allVals.reduce((a, b) => a + b);
    final currentAvg = sum / n;
    if ((currentAvg - target).abs() < 1e-6) {
      return (status: 'reached', count: 0, needed: 0.0);
    }
    if (currentAvg < target) {
      for (int k = 1; k <= 50; k++) {
        final perGrade = (target * (n + k) - sum) / k;
        if (perGrade <= 10) {
          return (status: 'reachable', count: k, needed: _roundToStep(math.max(4.0, perGrade), true));
        }
      }
      return (status: 'impossible', count: 0, needed: 0.0);
    } else {
      if (target <= 4 + 1e-6) return (status: 'impossible', count: 0, needed: 0.0);
      final kMinRaw = (sum - target * n) / (target - 4);
      final kMin = kMinRaw.ceil().clamp(1, 50);
      if (kMin > 50) return (status: 'impossible', count: 0, needed: 0.0);
      final perGrade = (target * (n + kMin) - sum) / kMin;
      return (status: 'reachable', count: kMin, needed: _roundToStep(math.max(4.0, perGrade), false));
    }
  }

  void _addGrade() {
    final val = double.tryParse(_inputCtrl.text.replaceAll(',', '.'));
    if (val == null || val < 1 || val > 10) return;
    setState(() { _extraGrades.add(val); _inputCtrl.clear(); });
  }

  void _resetDraft() {
    setState(() { _removedIds.clear(); _extraGrades.clear(); _targetCtrl.clear(); });
  }

  @override
  Widget build(BuildContext context) {
    final color = AppTheme.colorForSubject(widget.subject.subjectName);
    final simAvg = _simAverage;
    final origAvg = widget.subject.average;
    final screenHeight = MediaQuery.of(context).size.height;
    final heightDelta = 10 / screenHeight;
    final initialChildSize = (0.88 - heightDelta).clamp(0.0, 1.0) as double;
    final maxChildSize = (0.95 - heightDelta).clamp(0.0, 1.0) as double;
    final minChildSize = (0.5 - heightDelta).clamp(0.0, 1.0) as double;

    return DraggableScrollableSheet(
      initialChildSize: initialChildSize,
      maxChildSize: maxChildSize,
      minChildSize: minChildSize,
      snap: true,
      snapSizes: [minChildSize, initialChildSize, maxChildSize],
      shouldCloseOnMinExtent: true,
      builder: (_, scrollCtrl) {
        if (!_scrollResetQueued) {
          _scrollResetQueued = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !scrollCtrl.hasClients) return;
            scrollCtrl.jumpTo(0);
          });
        }

        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          behavior: HitTestBehavior.opaque,
          child: Container(
            decoration: BoxDecoration(
              color: context.appBg,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: context.appBorder, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.subject.subjectName,
                              style: TextStyle(
                                fontSize: 20, fontWeight: FontWeight.w700,
                                color: context.appTextPrimary, letterSpacing: -0.3,
                              ),
                            ),
                            if (widget.subject.teacherName.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.subject.teacherName,
                                style: TextStyle(fontSize: 13, color: context.appTextSecondary),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification) FocusScope.of(context).unfocus();
                      return false;
                    },
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // ── KPI Cards: Durchschnitt + Notenverhältnis ──────
                        Row(
                          children: [
                            Expanded(
                              child: _buildAvgCard(context, simAvg, origAvg),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _buildRatioCard(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        // ── KPI Card: Was brauche ich? ────────────────────
                        _buildTargetCard(context),
                        const SizedBox(height: 14),
                        // ── Notentrend ────────────────────────────────────
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text('Notentrend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
                                        Text('Verlauf aller Noten', style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
                                      ],
                                    ),
                                  ),
                                  if (_hasDraft)
                                    GestureDetector(
                                      onTap: _resetDraft,
                                      child: Row(
                                        children: [
                                          Icon(CupertinoIcons.arrow_counterclockwise, size: 12, color: context.appTextTertiary),
                                          const SizedBox(width: 4),
                                          Text('Zurücksetzen', style: TextStyle(fontSize: 12, color: context.appTextTertiary)),
                                        ],
                                      ),
                                    )
                                  else
                                    Row(
                                      children: [
                                        Container(width: 14, height: 2, color: color),
                                        const SizedBox(width: 4),
                                        Text('Noten', style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                                        const SizedBox(width: 8),
                                        Container(width: 14, height: 2, color: AppTheme.danger.withValues(alpha: 0.5)),
                                        const SizedBox(width: 4),
                                        Text('Trend', style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                                      ],
                                    ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 150,
                                child: _TrendChart(
                                  grades: widget.subject.grades,
                                  extraGrades: _extraGrades,
                                  removedIndices: _removedIndicesForChart,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        // ── Noten-Liste ───────────────────────────────────
                        if (widget.subject.grades.isNotEmpty)
                          _buildGradeList(context),
                        const SizedBox(height: 12),
                        // ── Mittelwert-Rechner ────────────────────────────
                        _buildCalculator(context),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ── Avg KPI card ──────────────────────────────────────────────────────────────

  Widget _buildAvgCard(BuildContext context, double? simAvg, double? origAvg) {
    final liveVals = _allGradeValues;
    final bestGrade = liveVals.isEmpty ? null : liveVals.reduce(math.max);
    final teacherDelta = (simAvg != null && origAvg != null) ? simAvg - origAvg : null;
    final color = simAvg != null ? _gradeColor(simAvg) : context.appTextSecondary;
    final count = liveVals.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
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
                    Text('Durchschnitt',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
                    Text(
                      _hasDraft ? '$count Noten · Simulation' : '$count Noten',
                      style: TextStyle(fontSize: 10, color: context.appTextTertiary),
                    ),
                  ],
                ),
              ),
              if (_hasDraft && teacherDelta != null && teacherDelta.abs() > 0.005)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: (teacherDelta >= 0 ? AppTheme.tint : AppTheme.danger).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        teacherDelta >= 0 ? Icons.trending_up_rounded : Icons.trending_down_rounded,
                        size: 11,
                        color: teacherDelta >= 0 ? AppTheme.tint : AppTheme.danger,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        _fmtGrade(teacherDelta.abs()),
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: teacherDelta >= 0 ? AppTheme.tint : AppTheme.danger,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            simAvg != null ? _fmtGrade(simAvg) : '—',
            style: TextStyle(
              fontSize: 30, fontWeight: FontWeight.w700, color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 4),
          if (_hasDraft && origAvg != null)
            Text('Lehrer-Schnitt ${_fmtGrade(origAvg)}',
                style: TextStyle(fontSize: 10, color: context.appTextTertiary))
          else if (bestGrade != null)
            Text('Beste ${_fmtGrade(bestGrade)}',
                style: TextStyle(fontSize: 10, color: context.appTextTertiary))
          else
            const SizedBox.shrink(),
        ],
      ),
    );
  }

  // ── Ratio KPI card ────────────────────────────────────────────────────────────

  Widget _buildRatioCard(BuildContext context) {
    final liveVals = _allGradeValues;
    final pos = liveVals.where((v) => v >= 6).length;
    final neg = liveVals.where((v) => v < 6).length;
    final total = pos + neg;
    final passRate = total > 0 ? pos / total : 0.0;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Notenverhältnis',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
              Text('Genügend · Ungenügend',
                  style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('$pos',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.tint,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(' / ', style: TextStyle(fontSize: 16, color: context.appTextTertiary)),
              ),
              Text('$neg',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.danger,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 5,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(width: c.maxWidth, height: 5, color: AppTheme.danger.withValues(alpha: 0.2)),
                    Container(width: c.maxWidth * passRate, height: 5, color: AppTheme.tint),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Was brauche ich? KPI card ─────────────────────────────────────────────────

  Widget _buildTargetCard(BuildContext context) {
    final result = _calcRequired();
    final hasInput = _targetCtrl.text.isNotEmpty;

    String resultText;
    Color resultColor;
    String hintText;

    if (!hasInput || result == null) {
      resultText = '—';
      resultColor = context.appTextTertiary;
      hintText = hasInput
          ? 'Bitte gib eine Zahl zwischen 1 und 10 ein'
          : 'Trage einen Zielschnitt ein';
    } else if (result.status == 'reached') {
      resultText = 'erreicht';
      resultColor = AppTheme.tint;
      hintText = 'Ziel ist mit dem aktuellen Schnitt schon erreicht';
    } else if (result.status == 'impossible') {
      resultText = 'unmöglich';
      resultColor = AppTheme.danger;
      hintText = 'Ziel ist mit weiteren Noten nicht mehr erreichbar';
    } else {
      resultColor = _gradeColor(result.needed);
      if (result.count == 1) {
        resultText = _fmtGrade(result.needed);
        hintText = 'Nächste Note für dein Ziel';
      } else {
        resultText = '${result.count}× ${_fmtGrade(result.needed)}';
        hintText = '${result.count}x ${_fmtGrade(result.needed)}, um den Schnitt zu erreichen';
      }
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
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
                    Text('Was brauche ich?',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
                    Text('Zielnote-Rechner',
                        style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                  ],
                ),
              ),
              Icon(CupertinoIcons.scope, size: 14, color: context.appTextSecondary),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _targetCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 15, color: context.appTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'Ziel',
                    hintStyle: TextStyle(fontSize: 14, color: context.appTextTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: context.appBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text('→', style: TextStyle(fontSize: 18, color: context.appTextTertiary)),
              ),
              Expanded(
                flex: 3,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  decoration: BoxDecoration(
                    color: hasInput && result != null
                        ? resultColor.withValues(alpha: 0.1)
                        : context.appBg,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: hasInput && result != null
                          ? resultColor.withValues(alpha: 0.3)
                          : context.appBorder,
                    ),
                  ),
                  child: Text(
                    resultText,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700,
                      color: hasInput && result != null ? resultColor : context.appTextTertiary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(hintText, style: TextStyle(fontSize: 11, color: context.appTextTertiary)),
        ],
      ),
    );
  }

  // ── Noten-Liste card ──────────────────────────────────────────────────────────

  Widget _buildGradeList(BuildContext context) {
    final grades = List<GradeEntry>.from(widget.subject.grades)
      ..sort((a, b) => b.date.compareTo(a.date));
    final activeCount = grades.where((g) => !_removedIds.contains(g.id)).length;
    final excludedCount = _removedIds.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Noten-Liste',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
          Text(
            '$activeCount aktiv · $excludedCount ausgeschlossen',
            style: TextStyle(fontSize: 11, color: context.appTextSecondary),
          ),
          const SizedBox(height: 12),
          if (grades.isEmpty)
            Text('Keine Noten erfasst',
                style: TextStyle(fontSize: 13, color: context.appTextTertiary))
          else
            ...grades.map((g) {
              final isRemoved = _removedIds.contains(g.id);
              final gc = _gradeColor(g.markDisplayValue);
              final label = g.text.isNotEmpty
                  ? g.text
                  : g.examType.isNotEmpty
                  ? g.examType
                  : '—';
              final dateShort = _fmtDateShort(g.date);
              final rel = _relativeDate(g.date);
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              color: isRemoved ? context.appTextTertiary : context.appTextPrimary,
                              decoration: isRemoved ? TextDecoration.lineThrough : null,
                              decorationColor: context.appTextTertiary,
                            ),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            '$dateShort · $rel',
                            style: TextStyle(fontSize: 10, color: context.appTextTertiary),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: (isRemoved ? context.appTextTertiary : gc).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        g.markName,
                        style: TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w700,
                          color: isRemoved ? context.appTextTertiary : gc,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () => setState(() {
                        if (isRemoved) {
                          _removedIds.remove(g.id);
                        } else {
                          _removedIds.add(g.id);
                        }
                      }),
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: context.appBg,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          isRemoved
                              ? CupertinoIcons.arrow_counterclockwise
                              : CupertinoIcons.trash,
                          size: 14,
                          color: isRemoved ? AppTheme.accent : context.appTextTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  // ── Mittelwert-Rechner card ───────────────────────────────────────────────────

  Widget _buildCalculator(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Mittelwert-Rechner',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
          Text('Eigene Noten zum Spielen',
              style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  style: TextStyle(fontSize: 15, color: context.appTextPrimary),
                  decoration: InputDecoration(
                    hintText: 'z.B. 7,5',
                    hintStyle: TextStyle(fontSize: 13, color: context.appTextTertiary),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    filled: true,
                    fillColor: context.appBg,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: context.appBorder),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: AppTheme.accent),
                    ),
                    isDense: true,
                  ),
                  onSubmitted: (_) => _addGrade(),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: _addGrade,
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(CupertinoIcons.add, size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_extraGrades.isEmpty)
            Text('Noch keine eigenen Noten',
                style: TextStyle(fontSize: 12, color: context.appTextTertiary))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: _extraGrades.asMap().entries.map((e) {
                final gc = _gradeColor(e.value);
                return GestureDetector(
                  onTap: () => setState(() => _extraGrades.removeAt(e.key)),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                    decoration: BoxDecoration(
                      color: gc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: gc.withValues(alpha: 0.25)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Text(
                          _fmtGrade(e.value),
                          style: TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w700, color: gc,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Icon(CupertinoIcons.trash, size: 11,
                            color: const Color(0xFF8E8E93)),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('Schnell-Test:',
                  style: TextStyle(fontSize: 11, color: context.appTextTertiary)),
              ...[4, 5, 6, 7, 8, 9, 10].map((v) {
                final gc = _gradeColor(v.toDouble());
                return GestureDetector(
                  onTap: () => setState(() => _extraGrades.add(v.toDouble())),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: gc.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: gc.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '$v',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700, color: gc,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                );
              }),
            ],
          ),
        ],
      ),
    );
  }
}

// ─── Trend chart ───────────────────────────────────────────────────────────────

class _TrendChart extends StatelessWidget {
  final List<GradeEntry> grades;
  final List<double> extraGrades;
  final Set<int> removedIndices;
  final Color color;
  const _TrendChart({
    required this.grades,
    required this.extraGrades,
    required this.removedIndices,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TrendPainter(
        grades: grades,
        extraGrades: extraGrades,
        removedIndices: removedIndices,
        lineColor: color,
        borderColor: context.appBorder,
        labelColor: context.appTextTertiary,
      ),
      size: Size.infinite,
    );
  }
}

class _TrendPainter extends CustomPainter {
  final List<GradeEntry> grades;
  final List<double> extraGrades;
  final Set<int> removedIndices;
  final Color lineColor;
  final Color borderColor;
  final Color labelColor;

  const _TrendPainter({
    required this.grades,
    required this.extraGrades,
    required this.removedIndices,
    required this.lineColor,
    required this.borderColor,
    required this.labelColor,
  });

  static const double _minV = 1.0;
  static const double _maxV = 10.0;
  static const double _padH = 22.0;
  static const double _padV = 12.0;

  double _xOf(int i, int total, double width) {
    if (total <= 1) return _padH + (width - _padH * 2) / 2;
    return _padH + (i / (total - 1)) * (width - _padH * 2);
  }

  double _yOf(double v, double height) =>
      height - _padV - ((v - _minV) / (_maxV - _minV)) * (height - _padV * 2);

  @override
  void paint(Canvas canvas, Size size) {
    if (grades.isEmpty) return;

    final activeGrades = grades
        .asMap()
        .entries
        .where((e) => !removedIndices.contains(e.key))
        .map((e) => e.value)
        .toList();
    final allValues = [
      ...activeGrades.map((g) => g.markDisplayValue),
      ...extraGrades,
    ];
    final n = allValues.length;

    final gridPaint = Paint()..color = borderColor.withValues(alpha: 0.35)..strokeWidth = 0.5;
    for (final v in [4.0, 6.0, 7.0, 9.0]) {
      final y = _yOf(v, size.height);
      canvas.drawLine(Offset(_padH, y), Offset(size.width - 4, y), gridPaint);
      _drawText(canvas, v.toInt().toString(), Offset(0, y - 6), labelColor.withValues(alpha: 0.6), 9);
    }

    if (activeGrades.length >= 2) {
      final linePaint = Paint()
        ..color = lineColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round;
      final path = Path();
      for (int i = 0; i < activeGrades.length; i++) {
        final x = _xOf(i, n, size.width);
        final y = _yOf(activeGrades[i].markDisplayValue, size.height);
        if (i == 0) path.moveTo(x, y); else path.lineTo(x, y);
      }
      canvas.drawPath(path, linePaint);
    }

    final dotPaint = Paint()..color = lineColor;
    for (int i = 0; i < activeGrades.length; i++) {
      canvas.drawCircle(
        Offset(_xOf(i, n, size.width), _yOf(activeGrades[i].markDisplayValue, size.height)),
        3.5, dotPaint,
      );
    }

    if (extraGrades.isNotEmpty) {
      final dashPaint = Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final startIdx = activeGrades.length - 1;
      for (int i = startIdx; i < n - 1; i++) {
        _drawDashed(
          canvas, dashPaint,
          Offset(_xOf(i, n, size.width), _yOf(allValues[i], size.height)),
          Offset(_xOf(i + 1, n, size.width), _yOf(allValues[i + 1], size.height)),
        );
      }
      final extraDotPaint = Paint()..color = AppTheme.accent;
      for (int i = activeGrades.length; i < n; i++) {
        canvas.drawCircle(
          Offset(_xOf(i, n, size.width), _yOf(allValues[i], size.height)),
          4, extraDotPaint,
        );
      }
    }

    if (activeGrades.length >= 2) {
      final xs = List.generate(activeGrades.length, (i) => i.toDouble());
      final ys = activeGrades.map((g) => g.markDisplayValue).toList();
      final cnt = xs.length.toDouble();
      final sumX = xs.reduce((a, b) => a + b);
      final sumY = ys.reduce((a, b) => a + b);
      final sumXY = List.generate(xs.length, (i) => xs[i] * ys[i]).reduce((a, b) => a + b);
      final sumXX = xs.map((x) => x * x).reduce((a, b) => a + b);
      final denom = cnt * sumXX - sumX * sumX;
      if (denom.abs() > 0.0001) {
        final slope = (cnt * sumXY - sumX * sumY) / denom;
        final intercept = (sumY - slope * sumX) / cnt;
        final trendPaint = Paint()
          ..color = AppTheme.danger.withValues(alpha: 0.5)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke;
        canvas.drawLine(
          Offset(_xOf(0, n, size.width), _yOf(intercept, size.height)),
          Offset(_xOf(activeGrades.length - 1, n, size.width),
              _yOf(slope * (activeGrades.length - 1) + intercept, size.height)),
          trendPaint,
        );
      }
    }
  }

  void _drawDashed(Canvas canvas, Paint paint, Offset start, Offset end) {
    const dashLen = 5.0;
    const gapLen = 4.0;
    final total = (end - start).distance;
    if (total < 0.01) return;
    final dir = (end - start) / total;
    double drawn = 0;
    bool drawing = true;
    while (drawn < total) {
      final len = math.min(drawing ? dashLen : gapLen, total - drawn);
      if (drawing) canvas.drawLine(start + dir * drawn, start + dir * (drawn + len), paint);
      drawn += len;
      drawing = !drawing;
    }
  }

  void _drawText(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fontSize, color: color)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(_TrendPainter old) =>
      old.grades != grades ||
      old.extraGrades != extraGrades ||
      old.removedIndices.length != removedIndices.length ||
      old.borderColor != borderColor ||
      old.labelColor != labelColor;
}
