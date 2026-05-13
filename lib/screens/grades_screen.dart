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
  if (v >= 4) return AppTheme.orange;
  return AppTheme.danger;
}

// Detailed per-integer color used in donut chart
Color _gradeColorByRank(int grade) {
  switch (grade) {
    case 10: return const Color(0xFF30D158);
    case 9:  return const Color(0xFF00C7BE);
    case 8:  return const Color(0xFF0A84FF);
    case 7:  return const Color(0xFF5E5CE6);
    case 6:  return const Color(0xFFFFD60A);
    case 5:  return const Color(0xFFFF9F0A);
    case 4:  return const Color(0xFFFF453A);
    default: return const Color(0xFF636366);
  }
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
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                    child: Column(
                      children: [
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _KpiCardDurchschnitt(kpi: kpi)),
                              const SizedBox(width: 10),
                              Expanded(child: _KpiCardVerhaeltnis(kpi: kpi)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        IntrinsicHeight(
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(child: _KpiCardVerteilung(kpi: kpi)),
                              const SizedBox(width: 10),
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

class _KpiCardDurchschnitt extends StatefulWidget {
  final _KpiData kpi;
  const _KpiCardDurchschnitt({required this.kpi});

  @override
  State<_KpiCardDurchschnitt> createState() => _KpiCardDurchschnittState();
}

class _KpiCardDurchschnittState extends State<_KpiCardDurchschnitt> {
  int? _tappedIndex;
  final _sparklineKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final kpi = widget.kpi;
    final avg = kpi.avg;
    final color = avg != null ? _gradeColor(avg) : context.appTextSecondary;

    final tapped = _tappedIndex != null &&
        _tappedIndex! < kpi.sparkline.length &&
        _tappedIndex! < kpi.sparklineMonths.length;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Durchschnittsnote',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                avg != null ? _fmtNum(avg) : '—',
                style: TextStyle(
                  fontSize: 30, fontWeight: FontWeight.w700, color: color,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (kpi.delta != null) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  margin: const EdgeInsets.only(bottom: 4),
                  decoration: BoxDecoration(
                    color: (kpi.delta! >= 0 ? AppTheme.tint : AppTheme.danger).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${kpi.delta! >= 0 ? '▲' : '▼'} ${_fmtNum(kpi.delta!.abs())}',
                    style: TextStyle(
                      fontSize: 10, fontWeight: FontWeight.w700,
                      color: kpi.delta! >= 0 ? AppTheme.tint : AppTheme.danger,
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (kpi.sparkline.length >= 2) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTapDown: (d) {
                final box = _sparklineKey.currentContext?.findRenderObject() as RenderBox?;
                if (box == null) return;
                final n = kpi.sparkline.length;
                if (n < 2) return;
                final w = box.size.width;
                final x = d.localPosition.dx;
                int closest = 0;
                double minDist = double.infinity;
                for (int i = 0; i < n; i++) {
                  final dist = (i / (n - 1) * w - x).abs();
                  if (dist < minDist) { minDist = dist; closest = i; }
                }
                setState(() => _tappedIndex = _tappedIndex == closest ? null : closest);
              },
              child: SizedBox(
                key: _sparklineKey,
                width: double.infinity,
                height: 32,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    data: kpi.sparkline,
                    color: color,
                    tappedIndex: _tappedIndex,
                  ),
                ),
              ),
            ),
            if (tapped) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: color.withValues(alpha: 0.25)),
                    ),
                    child: Text(
                      '${kpi.sparklineMonths[_tappedIndex!]}  ${_fmtNum(kpi.sparkline[_tappedIndex!])}',
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: color),
                    ),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: 8),
          if (!tapped) ...[
            if (kpi.prevAvg != null)
              Text('Vormonat ${_fmtNum(kpi.prevAvg!)}',
                  style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
            if (kpi.bestGrade > 0)
              Text('Beste Note ${_fmtNum(kpi.bestGrade)}',
                  style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
          ] else ...[
            Text('Tippe erneut zum Schließen',
                style: TextStyle(fontSize: 9, color: context.appTextTertiary)),
          ],
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notenverhältnis',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('${kpi.pos}',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.tint,
                      fontFeatures: const [FontFeature.tabularFigures()])),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(' / ', style: TextStyle(fontSize: 16, color: context.appTextTertiary)),
              ),
              Text('${kpi.neg}',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: AppTheme.danger,
                      fontFeatures: const [FontFeature.tabularFigures()])),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 6,
              child: LayoutBuilder(
                builder: (_, c) => Stack(
                  children: [
                    Container(width: c.maxWidth, height: 6, color: AppTheme.danger.withValues(alpha: 0.2)),
                    Container(width: c.maxWidth * posRatio, height: 6, color: AppTheme.tint),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '${(kpi.passRate * 100).round()}% bestanden',
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.tint),
          ),
          const SizedBox(height: 8),
          Text('${kpi.pos} positiv · ${kpi.neg} negativ',
              style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
        ],
      ),
    );
  }
}

class _KpiCardVerteilung extends StatelessWidget {
  final _KpiData kpi;
  const _KpiCardVerteilung({required this.kpi});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Notenverteilung',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 8),
          Center(
            child: SizedBox(
              width: 90, height: 90,
              child: CustomPaint(painter: _DonutPainter(distribution: kpi.distribution)),
            ),
          ),
          const SizedBox(height: 8),
          if (kpi.modeGrade != null)
            Text('Häufigste: ${kpi.modeGrade}',
                style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
          Text('Median: ${_fmtNum(kpi.median, digits: 1)}',
              style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
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
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Kürzlich hinzugefügt',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: context.appTextSecondary)),
          const SizedBox(height: 8),
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
                padding: const EdgeInsets.only(bottom: 7),
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
  final Color color;
  final int? tappedIndex;
  const _SparklinePainter({required this.data, required this.color, this.tappedIndex});

  @override
  void paint(Canvas canvas, Size size) {
    if (data.length < 2) return;
    final minV = data.reduce(math.min);
    final maxV = data.reduce(math.max);
    final range = (maxV - minV).abs();

    double yOf(double v) => range < 0.001
        ? size.height / 2
        : size.height - (v - minV) / range * (size.height - 4) - 2;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.75)
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
    canvas.drawPath(path, paint);

    // End dot
    final endY = yOf(data.last);
    canvas.drawCircle(Offset(size.width, endY), 2.5, Paint()..color = color);

    // Tapped point highlight
    if (tappedIndex != null && tappedIndex! < data.length) {
      final tx = tappedIndex! / (data.length - 1) * size.width;
      final ty = yOf(data[tappedIndex!]);
      canvas.drawCircle(Offset(tx, ty), 4.5,
          Paint()..color = color.withValues(alpha: 0.25));
      canvas.drawCircle(Offset(tx, ty), 2.8, Paint()..color = color);
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
  const _DonutPainter({required this.distribution});

  @override
  void paint(Canvas canvas, Size size) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) return;
    const labelReserve = 18.0;
    final availR = (math.min(size.width, size.height) / 2) - labelReserve;
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 16.0;
    final arcRadius = availR - strokeWidth / 2;
    const gap = 0.035;
    double startAngle = -math.pi / 2;
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    final segmentMidAngles = <int, double>{};
    final segmentSweeps = <int, double>{};
    for (final entry in sorted) {
      final sweep = ((entry.value / total) * (math.pi * 2) - gap).clamp(0.01, math.pi * 2);
      final paint = Paint()
        ..color = _gradeColorByRank(entry.key)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
        startAngle, sweep, false, paint,
      );
      segmentMidAngles[entry.key] = startAngle + sweep / 2;
      segmentSweeps[entry.key] = sweep;
      startAngle += sweep + gap;
    }

    for (final entry in sorted) {
      if ((segmentSweeps[entry.key] ?? 0) < 0.18) continue;
      final midAngle = segmentMidAngles[entry.key]!;
      final color = _gradeColorByRank(entry.key);

      final tickStart = Offset(
        center.dx + (arcRadius + strokeWidth / 2 + 1) * math.cos(midAngle),
        center.dy + (arcRadius + strokeWidth / 2 + 1) * math.sin(midAngle),
      );
      final tickEnd = Offset(
        center.dx + (arcRadius + strokeWidth / 2 + 7) * math.cos(midAngle),
        center.dy + (arcRadius + strokeWidth / 2 + 7) * math.sin(midAngle),
      );
      canvas.drawLine(tickStart, tickEnd,
          Paint()..color = color.withValues(alpha: 0.8)..strokeWidth = 1.2);

      final labelR = arcRadius + strokeWidth / 2 + 14;
      final lx = center.dx + labelR * math.cos(midAngle);
      final ly = center.dy + labelR * math.sin(midAngle);
      final tp = TextPainter(
        text: TextSpan(
          text: '${entry.key}',
          style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: color),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      final tx = (lx - tp.width / 2).clamp(0.0, size.width - tp.width);
      final ty = (ly - tp.height / 2).clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(tx, ty));
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.distribution != distribution;
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
  final Set<int> _removedIndices = {};
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  String? _inputError;
  bool _scrollResetQueued = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<double> get _allGradeValues => [
    ...widget.subject.grades
        .asMap()
        .entries
        .where((e) => !_removedIndices.contains(e.key))
        .map((e) => e.value.markDisplayValue),
    ..._extraGrades,
  ];

  double? get _simAverage {
    final all = _allGradeValues;
    if (all.isEmpty) return null;
    return all.reduce((a, b) => a + b) / all.length;
  }

  Color _gradeColor(double v) {
    if (v >= 6) return AppTheme.tint;
    if (v >= 4) return AppTheme.orange;
    return AppTheme.danger;
  }

  String _fmtAvg(double v) {
    final s = v.toStringAsFixed(3);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.?$'), '');
  }

  void _addGrade() {
    final val = double.tryParse(_inputCtrl.text.replaceAll(',', '.'));
    if (val == null || val < 1 || val > 10) {
      setState(() => _inputError = 'Bitte eine Note zwischen 1 und 10 eingeben');
      return;
    }
    setState(() { _extraGrades.add(val); _inputCtrl.clear(); _inputError = null; });
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
          onTap: () => _focusNode.unfocus(),
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
                        child: Text(
                          widget.subject.subjectName,
                          style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700,
                            color: context.appTextPrimary, letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (n) {
                      if (n is ScrollStartNotification) _focusNode.unfocus();
                      return false;
                    },
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStatCard(
                                label: 'Durchschnitt',
                                value: origAvg != null
                                    ? origAvg.toStringAsFixed(3).replaceAll(RegExp(r'0+4'), '').replaceAll(RegExp(r'\.\$'), '')
                                    : '—',
                                valueColor: origAvg != null ? _gradeColor(origAvg) : context.appTextSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MiniStatCard(
                                label: 'Pos. / Neg.',
                                value: '${widget.subject.positiveCount} / ${widget.subject.negativeCount}',
                                valueColor: context.appTextPrimary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MiniStatCard(
                                label: 'Noten',
                                value: '${widget.subject.grades.length}',
                                valueColor: context.appTextPrimary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
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
                                        Text('Trend', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
                                        Text('Notenentwicklung', style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
                                      ],
                                    ),
                                  ),
                                  Row(
                                    children: [
                                      Container(width: 14, height: 2, color: color),
                                      const SizedBox(width: 4),
                                      Text('Noten', style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                                      const SizedBox(width: 10),
                                      Container(width: 14, height: 2, color: AppTheme.danger.withValues(alpha: 0.5)),
                                      const SizedBox(width: 4),
                                      Text('Trend', style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                                      if (_extraGrades.isNotEmpty) ...[
                                        const SizedBox(width: 10),
                                        Container(width: 14, height: 2, color: AppTheme.accent.withValues(alpha: 0.7)),
                                        const SizedBox(width: 4),
                                        Text('Simulation', style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
                                      ],
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
                                  removedIndices: _removedIndices,
                                  color: color,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(14)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Mittelwert-Rechner', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: context.appTextPrimary)),
                              const SizedBox(height: 2),
                              Text('Simuliere zukünftige Noten', style: TextStyle(fontSize: 11, color: context.appTextSecondary)),
                              const SizedBox(height: 16),
                              if (simAvg != null)
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        _fmtAvg(simAvg),
                                        style: TextStyle(
                                          fontSize: 40, fontWeight: FontWeight.w700,
                                          color: _gradeColor(simAvg),
                                          fontFeatures: const [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      if (_extraGrades.isNotEmpty && origAvg != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                          decoration: BoxDecoration(
                                            color: (simAvg >= origAvg ? AppTheme.success : AppTheme.danger).withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            simAvg > origAvg
                                                ? '↑ ${(simAvg - origAvg).abs().toStringAsFixed(3).replaceAll(RegExp(r'0+\$'), '').replaceAll(RegExp(r'\.\$'), '')} besser'
                                                : simAvg < origAvg
                                                ? '↓ ${(origAvg - simAvg).abs().toStringAsFixed(3).replaceAll(RegExp(r'0+\$'), '').replaceAll(RegExp(r'\.\$'), '')} schlechter'
                                                : 'Kein Unterschied',
                                            style: TextStyle(
                                              fontSize: 12, fontWeight: FontWeight.w600,
                                              color: simAvg >= origAvg ? AppTheme.success : AppTheme.danger,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 16),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (widget.subject.grades.isNotEmpty) ...[
                                    Text('Vorhandene Noten', style: TextStyle(fontSize: 11, color: context.appTextTertiary)),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8, runSpacing: 7,
                                      children: widget.subject.grades.asMap().entries.map((e) {
                                        final removed = _removedIndices.contains(e.key);
                                        final raw = e.value.markDisplayValue;
                                        final label = raw.toStringAsFixed(3)
                                            .replaceAll(RegExp(r'0+$'), '')
                                            .replaceAll(RegExp(r'\.?$'), '');
                                        final gc = removed
                                            ? context.appTextTertiary
                                            : _gradeColor(raw).withValues(alpha: 0.85);
                                        return GestureDetector(
                                          onTap: () => setState(() {
                                            if (removed) _removedIndices.remove(e.key);
                                            else _removedIndices.add(e.key);
                                          }),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: removed ? context.appSurface : gc.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(9),
                                              border: Border.all(
                                                color: removed
                                                    ? context.appBorder.withValues(alpha: 0.35)
                                                    : gc.withValues(alpha: 0.35),
                                              ),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(label,
                                                    style: TextStyle(
                                                      fontSize: 15,
                                                      fontWeight: removed ? FontWeight.w400 : FontWeight.w600,
                                                      color: gc,
                                                      decoration: removed ? TextDecoration.lineThrough : null,
                                                      decorationColor: context.appTextTertiary.withValues(alpha: 0.6),
                                                    )),
                                                const SizedBox(width: 5),
                                                Icon(
                                                  removed ? CupertinoIcons.plus : CupertinoIcons.xmark,
                                                  size: 12,
                                                  color: removed
                                                      ? context.appTextTertiary.withValues(alpha: 0.5)
                                                      : AppTheme.danger,
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  if (_extraGrades.isNotEmpty) ...[
                                    Text('Testnoten', style: TextStyle(fontSize: 11, color: context.appTextTertiary)),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8, runSpacing: 7,
                                      children: _extraGrades.asMap().entries.map((e) {
                                        final gc = _gradeColor(e.value);
                                        final label = e.value.toStringAsFixed(3)
                                            .replaceAll(RegExp(r'0+$'), '')
                                            .replaceAll(RegExp(r'\.?$'), '');
                                        return GestureDetector(
                                          onTap: () => setState(() => _extraGrades.removeAt(e.key)),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                                            decoration: BoxDecoration(
                                              color: gc.withValues(alpha: 0.12),
                                              borderRadius: BorderRadius.circular(9),
                                              border: Border.all(color: gc.withValues(alpha: 0.35)),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: gc)),
                                                const SizedBox(width: 5),
                                                Icon(CupertinoIcons.xmark, size: 11, color: gc.withValues(alpha: 0.7)),
                                              ],
                                            ),
                                          ),
                                        );
                                      }).toList(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ],
                              ),
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap: () {},
                                      child: CupertinoTextField(
                                        focusNode: _focusNode,
                                        controller: _inputCtrl,
                                        placeholder: 'Note eingeben (1–10)',
                                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                        style: TextStyle(color: context.appTextPrimary, fontSize: 14),
                                        placeholderStyle: TextStyle(color: context.appTextTertiary, fontSize: 14),
                                        decoration: BoxDecoration(
                                          color: context.appBg,
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _inputError != null ? AppTheme.danger : context.appBorder,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        onSubmitted: (_) => _addGrade(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  CupertinoButton(
                                    color: AppTheme.accent,
                                    borderRadius: BorderRadius.circular(10),
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    minimumSize: Size.zero,
                                    onPressed: _addGrade,
                                    child: const Icon(CupertinoIcons.plus, size: 18, color: Colors.white),
                                  ),
                                ],
                              ),
                              if (_inputError != null) ...[
                                const SizedBox(height: 6),
                                Text(_inputError!, style: const TextStyle(fontSize: 11, color: AppTheme.danger)),
                              ],
                            ],
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
      },
    );
  }
}

// ─── Mini stat card ────────────────────────────────────────────────────────────

class _MiniStatCard extends StatelessWidget {
  final String label;
  final String value;
  final Color valueColor;
  const _MiniStatCard({required this.label, required this.value, required this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: context.appSurface, borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
          const SizedBox(height: 4),
          Text(value,
              style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700, color: valueColor,
                fontFeatures: const [FontFeature.tabularFigures()],
              )),
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
