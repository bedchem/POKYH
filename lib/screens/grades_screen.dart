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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    // Show cached data immediately — no spinner if we already have data.
    final cached = widget.service.cachedGrades;
    if (cached != null && !forceRefresh) {
      setState(() {
        _subjects = cached;
        _loading = false;
      });
      // Refresh silently in background.
      _refreshInBackground();
      return;
    }

    setState(() {
      _loading = _subjects.isEmpty;
      _error = null;
    });
    try {
      final grades = await widget.service.getAllGrades(
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _subjects = grades;
          _loading = false;
        });
      }
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
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = simplifyErrorMessage(e);
          _loading = false;
        });
      }
    }
  }

  Future<void> _refreshInBackground() async {
    try {
      final grades = await widget.service.getAllGrades(forceRefresh: true);
      if (mounted) setState(() => _subjects = grades);
    } catch (_) {}
  }

  double? get _totalAverage {
    final allGrades = _subjects
        .expand((s) => s.grades)
        .map((g) => g.markDisplayValue)
        .toList();
    if (allGrades.isEmpty) return null;
    return allGrades.reduce((a, b) => a + b) / allGrades.length;
  }

  @override
  Widget build(BuildContext context) {
    final scrollView = CustomScrollView(
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
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: context.appSurface,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Platform.isIOS
                              ? CupertinoIcons.chevron_left
                              : Icons.arrow_back,
                          size: 16,
                          color: context.appTextSecondary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text(
                      'Noten',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: context.appTextPrimary,
                        letterSpacing: -0.5,
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
                      style: TextStyle(
                        fontSize: 14,
                        color: context.appTextSecondary,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),

        // ── Overview + Notenverteilung (combined) ──
        if (!_loading && _error == null && _subjects.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: _OverviewAndDistributionCard(
                average: _totalAverage,
                subjects: _subjects,
              ),
            ),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ── Content ──
        if (_loading)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CupertinoActivityIndicator(radius: 14),
                  const SizedBox(height: 14),
                  Text(
                    'Noten werden geladen…',
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
                    child: const Center(
                      child: Icon(
                        CupertinoIcons.exclamationmark_triangle_fill,
                        color: AppTheme.danger,
                        size: 24,
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: context.appTextSecondary),
                  ),
                  const SizedBox(height: 18),
                  CupertinoButton(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 7,
                    ),
                    color: AppTheme.accent,
                    borderRadius: BorderRadius.circular(9),
                    minimumSize: Size.zero,
                    onPressed: _load,
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
          )
        else if (_subjects.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: Center(
              child: Text(
                'Keine Noten vorhanden',
                style: TextStyle(color: context.appTextSecondary, fontSize: 15),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _SubjectCard(subject: _subjects[i]),
                ),
                childCount: _subjects.length,
              ),
            ),
          ),
      ],
    );

    return Scaffold(
      backgroundColor: context.appBg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          child: scrollView,
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Combined overview + donut card
// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewAndDistributionCard extends StatelessWidget {
  final double? average;
  final List<SubjectGrades> subjects;
  const _OverviewAndDistributionCard({
    required this.average,
    required this.subjects,
  });

  static Color gradeColor(int grade) {
    switch (grade) {
      case 10:
        return const Color(0xFF30D158); // grün
      case 9:
        return const Color(0xFF00C7BE); // türkis
      case 8:
        return const Color(0xFF0A84FF); // blau
      case 7:
        return const Color(0xFF5E5CE6); // lila
      case 6:
        return const Color(0xFFFFD60A); // gelb
      case 5:
        return const Color(0xFFFF9F0A); // orange
      case 4:
        return const Color(0xFFFF453A); // rot
      default:
        return const Color(0xFF636366);
    }
  }

  /// Exakte Werte für Donut-Segmente (keine Rundung)
  Map<double, int> _buildDistribution() {
    final map = <double, int>{};
    for (final s in subjects) {
      for (final g in s.grades) {
        final v = g.markDisplayValue;
        map[v] = (map[v] ?? 0) + 1;
      }
    }
    return map;
  }

  /// Gruppiert nach ganzen Zahlen (10,9,8,7,6,5,4) für die Legende
  Map<int, int> _buildGroupedDistribution() {
    final map = <int, int>{};
    for (final s in subjects) {
      for (final g in s.grades) {
        final v = g.markDisplayValue.round();
        map[v] = (map[v] ?? 0) + 1;
      }
    }
    return map;
  }

  @override
  Widget build(BuildContext context) {
    final totalGrades = subjects.fold<int>(0, (s, e) => s + e.grades.length);
    final positive = subjects.fold<int>(0, (s, e) => s + e.positiveCount);
    final negative = subjects.fold<int>(0, (s, e) => s + e.negativeCount);
    final groupedDist = _buildGroupedDistribution();
    final sortedEntries = (groupedDist.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key)));

    return Container(
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          // ── Top: average summary ──
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                if (average != null)
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: _OverviewAndDistributionCard.gradeColor(
                        average!.round(),
                      ).withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _OverviewAndDistributionCard.gradeColor(
                          average!.round(),
                        ).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Center(
                      child: Text(
                        average!.toStringAsFixed(2),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: _OverviewAndDistributionCard.gradeColor(
                            average!.round(),
                          ),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 18),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Gesamtdurchschnitt',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          _StatPill(
                            label: '$totalGrades',
                            sub: 'Noten',
                            color: AppTheme.accent,
                          ),
                          const SizedBox(width: 8),
                          _StatPill(
                            label: '$positive',
                            sub: 'positiv',
                            color: AppTheme.success,
                          ),
                          const SizedBox(width: 8),
                          _StatPill(
                            label: '$negative',
                            sub: 'negativ',
                            color: AppTheme.danger,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ──
          Divider(color: context.appBorder.withValues(alpha: 0.5), height: 1),

          // ── Bottom: donut + legend ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(
                  width: 110,
                  height: 110,
                  child: CustomPaint(
                    painter: _DonutPainter(distribution: groupedDist),
                  ),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notenverteilung',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: context.appTextPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 12,
                        runSpacing: 8,
                        children: sortedEntries.map((e) {
                          final color = _OverviewAndDistributionCard.gradeColor(
                            e.key,
                          );
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${e.value}×',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: color,
                                ),
                              ),
                            ],
                          );
                        }).toList(),
                      ),
                    ],
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

class _DonutPainter extends CustomPainter {
  final Map<int, int> distribution;
  const _DonutPainter({required this.distribution});

  @override
  void paint(Canvas canvas, Size size) {
    final total = distribution.values.fold(0, (a, b) => a + b);
    if (total == 0) return;
    // Reserve 18px on each side for labels, donut fits in remaining space
    const labelReserve = 18.0;
    final availR = (math.min(size.width, size.height) / 2) - labelReserve;
    final center = Offset(size.width / 2, size.height / 2);
    const strokeWidth = 16.0;
    final arcRadius = availR - strokeWidth / 2;
    const gap = 0.035;
    double startAngle = -math.pi / 2;
    final sorted = distribution.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));

    // Draw arcs + collect mid angles
    final segmentMidAngles = <int, double>{};
    final segmentSweeps = <int, double>{};
    for (final entry in sorted) {
      final sweep = ((entry.value / total) * (math.pi * 2) - gap).clamp(
        0.01,
        math.pi * 2,
      );
      final paint = Paint()
        ..color = _OverviewAndDistributionCard.gradeColor(entry.key)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: arcRadius),
        startAngle,
        sweep,
        false,
        paint,
      );
      segmentMidAngles[entry.key] = startAngle + sweep / 2;
      segmentSweeps[entry.key] = sweep;
      startAngle += sweep + gap;
    }

    // Draw tick lines + numbers — all within canvas bounds
    for (final entry in sorted) {
      if ((segmentSweeps[entry.key] ?? 0) < 0.18) continue;
      final midAngle = segmentMidAngles[entry.key]!;
      final color = _OverviewAndDistributionCard.gradeColor(entry.key);

      // Tick: from outer edge of arc to just inside label reserve
      final tickStart = Offset(
        center.dx + (arcRadius + strokeWidth / 2 + 1) * math.cos(midAngle),
        center.dy + (arcRadius + strokeWidth / 2 + 1) * math.sin(midAngle),
      );
      final tickEnd = Offset(
        center.dx + (arcRadius + strokeWidth / 2 + 7) * math.cos(midAngle),
        center.dy + (arcRadius + strokeWidth / 2 + 7) * math.sin(midAngle),
      );
      canvas.drawLine(
        tickStart,
        tickEnd,
        Paint()
          ..color = color.withValues(alpha: 0.8)
          ..strokeWidth = 1.2,
      );

      // Label right at tick end
      final labelR = arcRadius + strokeWidth / 2 + 14;
      final lx = center.dx + labelR * math.cos(midAngle);
      final ly = center.dy + labelR * math.sin(midAngle);
      final tp = TextPainter(
        text: TextSpan(
          text: '${entry.key}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      // Clamp so text never exits the canvas
      final tx = (lx - tp.width / 2).clamp(0.0, size.width - tp.width);
      final ty = (ly - tp.height / 2).clamp(0.0, size.height - tp.height);
      tp.paint(canvas, Offset(tx, ty));
    }
  }

  @override
  bool shouldRepaint(_DonutPainter old) => old.distribution != distribution;
}

class _StatPill extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  const _StatPill({
    required this.label,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        Text(sub, style: TextStyle(fontSize: 10, color: context.appTextTertiary)),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// Subject card
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectCard extends StatefulWidget {
  final SubjectGrades subject;
  const _SubjectCard({required this.subject});

  @override
  State<_SubjectCard> createState() => _SubjectCardState();
}

class _SubjectCardState extends State<_SubjectCard>
    with SingleTickerProviderStateMixin {
  bool _expanded = false;

  Color _gradeColor(double v) {
    if (v >= 9) return AppTheme.success;
    if (v >= 6.5) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return AppTheme.orange;
    return AppTheme.danger;
  }

  void _openDetail(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _SubjectDetailSheet(subject: widget.subject),
    );
  }

  @override
  Widget build(BuildContext context) {
    final avg = widget.subject.average;
    final color = AppTheme.colorForSubject(widget.subject.subjectName);

    return GestureDetector(
      onTap: () => setState(() => _expanded = !_expanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(14),
          border: _expanded
              ? Border.all(color: color.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.subject.subjectName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: context.appTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.subject.teacherName} \u00b7 ${widget.subject.grades.length} Noten',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.appTextSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),

                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _openDetail(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: context.appBorder.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: context.appBorder),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            CupertinoIcons.chart_bar_alt_fill,
                            size: 12,
                            color: context.appTextSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Detail',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  if (avg != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _gradeColor(avg).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _gradeColor(avg).withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        avg.toStringAsFixed(1),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _gradeColor(avg),
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),

                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: const Duration(milliseconds: 250),
                    child: Icon(
                      CupertinoIcons.chevron_down,
                      size: 14,
                      color: context.appTextTertiary,
                    ),
                  ),
                ],
              ),
            ),

            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Column(
                children: [
                  Divider(
                    color: context.appBorder.withValues(alpha: 0.5),
                    height: 1,
                    indent: 14,
                    endIndent: 14,
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
                    child: Column(
                      children: widget.subject.grades.map((g) {
                        final gc = _gradeColor(g.markDisplayValue);
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            children: [
                              Container(
                                constraints: const BoxConstraints(minWidth: 40),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: gc.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  g.markName,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: gc,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  g.text.isNotEmpty
                                      ? g.text
                                      : (g.examType.isNotEmpty
                                            ? g.examType
                                            : '\u2014'),
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: context.appTextSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 14),
                              Text(
                                g.dateFormatted,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: context.appTextTertiary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
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
// Subject detail bottom sheet
// ═══════════════════════════════════════════════════════════════════════════════

class _SubjectDetailSheet extends StatefulWidget {
  final SubjectGrades subject;
  const _SubjectDetailSheet({required this.subject});

  @override
  State<_SubjectDetailSheet> createState() => _SubjectDetailSheetState();
}

class _SubjectDetailSheetState extends State<_SubjectDetailSheet> {
  final List<double> _extraGrades = [];
  final Set<int> _removedIndices = {}; // indices of real grades toggled off
  final TextEditingController _inputCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode(); // FocusNode hinzufügen
  String? _inputError;
  bool _scrollResetQueued = false;

  @override
  void dispose() {
    _inputCtrl.dispose();
    _focusNode.dispose(); // FocusNode disposen
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
    if (v >= 9) return AppTheme.success;
    if (v >= 6.5) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return AppTheme.orange;
    return AppTheme.danger;
  }

  String _fmtAvg(double v) {
    // Max 3 decimal places, no trailing zeros
    final s = v.toStringAsFixed(3);
    return s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.?$'), '');
  }

  void _addGrade() {
    final val = double.tryParse(_inputCtrl.text.replaceAll(',', '.'));
    if (val == null || val < 1 || val > 10) {
      setState(
        () => _inputError = 'Bitte eine Note zwischen 1 und 10 eingeben',
      );
      return;
    }
    setState(() {
      _extraGrades.add(val);
      _inputCtrl.clear();
      _inputError = null;
    });
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
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                // Handle bar
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 4),
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.appBorder,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),

                // Header
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                  child: Row(
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.subject.subjectName,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  child: NotificationListener<ScrollNotification>(
                    onNotification: (notification) {
                      if (notification is ScrollStartNotification) {
                        _focusNode.unfocus();
                      }
                      return false;
                    },
                    child: ListView(
                      controller: scrollCtrl,
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 40),
                      children: [
                        // Stats row
                        Row(
                          children: [
                            Expanded(
                              child: _MiniStatCard(
                                label: 'Durchschnitt',
                                value: origAvg != null
                                    ? origAvg
                                          .toStringAsFixed(3)
                                          .replaceAll(RegExp(r'0+4'), '')
                                          .replaceAll(RegExp(r'\.\$'), '')
                                    : '—',
                                valueColor: origAvg != null
                                    ? _gradeColor(origAvg)
                                    : context.appTextSecondary,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MiniStatCard(
                                label: 'Pos. / Neg.',
                                value:
                                    '${widget.subject.positiveCount} / ${widget.subject.negativeCount}',
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

                        // Trend chart card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Trend',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: context.appTextPrimary,
                                          ),
                                        ),
                                        Text(
                                          'Notenentwicklung',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: context.appTextSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Legend
                                  Row(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 2,
                                        color: color,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Noten',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: context.appTextTertiary,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Container(
                                        width: 14,
                                        height: 2,
                                        color: AppTheme.danger.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Trend',
                                        style: TextStyle(
                                          fontSize: 10,
                                          color: context.appTextTertiary,
                                        ),
                                      ),
                                      if (_extraGrades.isNotEmpty) ...[
                                        const SizedBox(width: 10),
                                        Container(
                                          width: 14,
                                          height: 2,
                                          color: AppTheme.accent.withValues(
                                            alpha: 0.7,
                                          ),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Simulation',
                                          style: TextStyle(
                                            fontSize: 10,
                                            color: context.appTextTertiary,
                                          ),
                                        ),
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

                        // Mittelwert-Rechner card
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: context.appSurface,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Mittelwert-Rechner',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: context.appTextPrimary,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Simuliere zukünftige Noten',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: context.appTextSecondary,
                                ),
                              ),
                              const SizedBox(height: 16),

                              // Simulated average
                              if (simAvg != null)
                                Center(
                                  child: Column(
                                    children: [
                                      Text(
                                        _fmtAvg(simAvg),
                                        style: TextStyle(
                                          fontSize: 40,
                                          fontWeight: FontWeight.w700,
                                          color: _gradeColor(simAvg),
                                          fontFeatures: const [
                                            FontFeature.tabularFigures(),
                                          ],
                                        ),
                                      ),
                                      if (_extraGrades.isNotEmpty &&
                                          origAvg != null)
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 3,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                (simAvg >= origAvg
                                                        ? AppTheme.success
                                                        : AppTheme.danger)
                                                    .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              6,
                                            ),
                                          ),
                                          child: Text(
                                            simAvg > origAvg
                                                ? '\u2191 ${(simAvg - origAvg).abs().toStringAsFixed(3).replaceAll(RegExp(r'0+\$'), '').replaceAll(RegExp(r'\.\$'), '')} besser'
                                                : simAvg < origAvg
                                                ? '\u2193 ${(origAvg - simAvg).abs().toStringAsFixed(3).replaceAll(RegExp(r'0+\$'), '').replaceAll(RegExp(r'\.\$'), '')} schlechter'
                                                : 'Kein Unterschied',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: simAvg >= origAvg
                                                  ? AppTheme.success
                                                  : AppTheme.danger,
                                            ),
                                          ),
                                        ),
                                    ],
                                  ),
                                ),

                              const SizedBox(height: 16),

                              // All grades display
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Real grades — tap to toggle out/in
                                  if (widget.subject.grades.isNotEmpty) ...[
                                    Text(
                                      'Vorhandene Noten',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appTextTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 7,
                                      children: widget.subject.grades
                                          .asMap()
                                          .entries
                                          .map((e) {
                                            final removed = _removedIndices
                                                .contains(e.key);
                                            final raw =
                                                e.value.markDisplayValue;
                                            final label = raw
                                                .toStringAsFixed(3)
                                                .replaceAll(RegExp(r'0+$'), '')
                                                .replaceAll(
                                                  RegExp(r'\.?$'),
                                                  '',
                                                );
                                            final gc = removed
                                                ? context.appTextTertiary
                                                : _gradeColor(
                                                    raw,
                                                  ).withValues(alpha: 0.85);
                                            return GestureDetector(
                                              onTap: () => setState(() {
                                                if (removed) {
                                                  _removedIndices.remove(e.key);
                                                } else {
                                                  _removedIndices.add(e.key);
                                                }
                                              }),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: removed
                                                      ? context.appSurface
                                                      : gc.withValues(
                                                          alpha: 0.12,
                                                        ),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  border: Border.all(
                                                    color: removed
                                                        ? context.appBorder
                                                              .withValues(
                                                                alpha: 0.35,
                                                              )
                                                        : gc.withValues(
                                                            alpha: 0.35,
                                                          ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      label,
                                                      style: TextStyle(
                                                        fontSize: 15,
                                                        fontWeight: removed
                                                            ? FontWeight.w400
                                                            : FontWeight.w600,
                                                        color: gc,
                                                        decoration: removed
                                                            ? TextDecoration
                                                                  .lineThrough
                                                            : null,
                                                        decorationColor:
                                                            context.appTextTertiary
                                                                .withValues(
                                                                  alpha: 0.6,
                                                                ),
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Icon(
                                                      removed
                                                          ? CupertinoIcons.plus
                                                          : CupertinoIcons
                                                                .xmark,
                                                      size: 12,
                                                      color: removed
                                                          ? context.appTextTertiary
                                                                .withValues(
                                                                  alpha: 0.5,
                                                                )
                                                          : AppTheme.danger,
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          })
                                          .toList(),
                                    ),
                                    const SizedBox(height: 14),
                                  ],
                                  // Test grades (colored, tappable to remove)
                                  if (_extraGrades.isNotEmpty) ...[
                                    Text(
                                      'Testnoten',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: context.appTextTertiary,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 7,
                                      children: _extraGrades
                                          .asMap()
                                          .entries
                                          .map((e) {
                                            final gc = _gradeColor(e.value);
                                            final raw = e.value;
                                            final label = raw
                                                .toStringAsFixed(3)
                                                .replaceAll(RegExp(r'0+$'), '')
                                                .replaceAll(
                                                  RegExp(r'\.?$'),
                                                  '',
                                                );
                                            return GestureDetector(
                                              onTap: () => setState(
                                                () => _extraGrades.removeAt(
                                                  e.key,
                                                ),
                                              ),
                                              child: Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 12,
                                                      vertical: 7,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: gc.withValues(
                                                    alpha: 0.12,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(9),
                                                  border: Border.all(
                                                    color: gc.withValues(
                                                      alpha: 0.35,
                                                    ),
                                                  ),
                                                ),
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Text(
                                                      label,
                                                      style: TextStyle(
                                                        fontSize: 13,
                                                        fontWeight:
                                                            FontWeight.w700,
                                                        color: gc,
                                                      ),
                                                    ),
                                                    const SizedBox(width: 5),
                                                    Icon(
                                                      CupertinoIcons.xmark,
                                                      size: 11,
                                                      color: gc.withValues(
                                                        alpha: 0.7,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            );
                                          })
                                          .toList(),
                                    ),
                                    const SizedBox(height: 12),
                                  ],
                                ],
                              ),

                              // Input row
                              Row(
                                children: [
                                  Expanded(
                                    child: GestureDetector(
                                      onTap:
                                          () {}, // Verhindert, dass der Tap auf das Textfeld den Fokus entfernt
                                      child: CupertinoTextField(
                                        focusNode:
                                            _focusNode, // FocusNode zuweisen
                                        controller: _inputCtrl,
                                        placeholder: 'Note eingeben (1–10)',
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        style: TextStyle(
                                          color: context.appTextPrimary,
                                          fontSize: 14,
                                        ),
                                        placeholderStyle: TextStyle(
                                          color: context.appTextTertiary,
                                          fontSize: 14,
                                        ),
                                        decoration: BoxDecoration(
                                          color: context.appBg,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                          border: Border.all(
                                            color: _inputError != null
                                                ? AppTheme.danger
                                                : context.appBorder,
                                          ),
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        onSubmitted: (_) => _addGrade(),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  CupertinoButton(
                                    color: AppTheme.accent,
                                    borderRadius: BorderRadius.circular(10),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 16,
                                      vertical: 10,
                                    ),
                                    minimumSize: Size.zero,
                                    onPressed: _addGrade,
                                    child: const Icon(
                                      CupertinoIcons.plus,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),

                              if (_inputError != null) ...[
                                const SizedBox(height: 6),
                                Text(
                                  _inputError!,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: AppTheme.danger,
                                  ),
                                ),
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
  const _MiniStatCard({
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(fontSize: 10, color: context.appTextTertiary),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Trend chart (custom paint) ────────────────────────────────────────────────

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

    // Grid lines
    final gridPaint = Paint()
      ..color = borderColor.withValues(alpha: 0.35)
      ..strokeWidth = 0.5;
    for (final v in [4.0, 6.0, 7.0, 9.0]) {
      final y = _yOf(v, size.height);
      canvas.drawLine(Offset(_padH, y), Offset(size.width - 4, y), gridPaint);
      // Y label
      _drawText(
        canvas,
        v.toInt().toString(),
        Offset(0, y - 6),
        labelColor.withValues(alpha: 0.6),
        9,
      );
    }

    // Original line
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
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, linePaint);
    }

    // Dots for original
    final dotPaint = Paint()..color = lineColor;
    for (int i = 0; i < activeGrades.length; i++) {
      canvas.drawCircle(
        Offset(
          _xOf(i, n, size.width),
          _yOf(activeGrades[i].markDisplayValue, size.height),
        ),
        3.5,
        dotPaint,
      );
    }

    // Extra grades dashed
    if (extraGrades.isNotEmpty) {
      final dashPaint = Paint()
        ..color = AppTheme.accent.withValues(alpha: 0.8)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round;
      final startIdx = activeGrades.length - 1;
      for (int i = startIdx; i < n - 1; i++) {
        _drawDashed(
          canvas,
          dashPaint,
          Offset(_xOf(i, n, size.width), _yOf(allValues[i], size.height)),
          Offset(
            _xOf(i + 1, n, size.width),
            _yOf(allValues[i + 1], size.height),
          ),
        );
      }
      final extraDotPaint = Paint()..color = AppTheme.accent;
      for (int i = activeGrades.length; i < n; i++) {
        canvas.drawCircle(
          Offset(_xOf(i, n, size.width), _yOf(allValues[i], size.height)),
          4,
          extraDotPaint,
        );
      }
    }

    // Trend line (linear regression)
    if (activeGrades.length >= 2) {
      final xs = List.generate(activeGrades.length, (i) => i.toDouble());
      final ys = activeGrades.map((g) => g.markDisplayValue).toList();
      final cnt = xs.length.toDouble();
      final sumX = xs.reduce((a, b) => a + b);
      final sumY = ys.reduce((a, b) => a + b);
      final sumXY = List.generate(
        xs.length,
        (i) => xs[i] * ys[i],
      ).reduce((a, b) => a + b);
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
          Offset(
            _xOf(activeGrades.length - 1, n, size.width),
            _yOf(slope * (activeGrades.length - 1) + intercept, size.height),
          ),
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
      if (drawing) {
        canvas.drawLine(
          start + dir * drawn,
          start + dir * (drawn + len),
          paint,
        );
      }
      drawn += len;
      drawing = !drawing;
    }
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset,
    Color color,
    double fontSize,
  ) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: fontSize, color: color),
      ),
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
