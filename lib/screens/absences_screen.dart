import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../config/app_config.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import '../widgets/top_bar_actions.dart';
import 'login_screen.dart';

class AbsencesScreen extends StatefulWidget {
  final WebUntisService service;
  const AbsencesScreen({super.key, required this.service});

  @override
  State<AbsencesScreen> createState() => _AbsencesScreenState();
}

class _AbsencesScreenState extends State<AbsencesScreen> {
  List<AbsenceEntry> _absences = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final cached = widget.service.cachedAbsences;
    if (cached != null && !forceRefresh) {
      setState(() { _absences = cached; _loading = false; });
      _refreshInBackground();
      return;
    }
    setState(() { _loading = _absences.isEmpty; _error = null; });
    try {
      final absences = await widget.service.getAbsences(forceRefresh: forceRefresh);
      if (mounted) setState(() { _absences = absences; _loading = false; });
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

  Future<void> _refreshInBackground() async {
    try {
      final absences = await widget.service.getAbsences(forceRefresh: true);
      if (mounted) setState(() => _absences = absences);
    } catch (_) {}
  }

  int get _totalHours => _absences.fold(0, (s, a) => s + a.hours);
  int get _excusedHours =>
      _absences.where((a) => a.isExcused).fold(0, (s, a) => s + a.hours);
  int get _unexcusedHours => _totalHours - _excusedHours;

  double get _absenceRate {
    if (_totalHours == 0) return 0;
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    final elapsed = now.difference(DateTime(startYear, 9, 1)).inDays;
    final estimatedTotal = (elapsed * 5 / 7 * 0.85).round() * 7;
    if (estimatedTotal <= 0) return 0;
    return (_totalHours / estimatedTotal * 100).clamp(0, 100);
  }

  Map<String, List<AbsenceEntry>> get _grouped {
    final result = <String, List<AbsenceEntry>>{};
    for (final a in _absences) {
      final dt = a.startDateTime;
      result
          .putIfAbsent('${AppConfig.monthLabels[dt.month - 1]} ${dt.year}',
              () => [])
          .add(a);
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _load(forceRefresh: true),
          color: AppTheme.orange,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              // ── Header ──────────────────────────────────────────────────
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          width: 36,
                          height: 36,
                          decoration: BoxDecoration(
                            color: AppTheme.surface,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: AppTheme.border.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Icon(
                            Platform.isIOS
                                ? CupertinoIcons.chevron_left
                                : Icons.arrow_back,
                            size: 16,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Abwesenheiten',
                              style: TextStyle(
                                fontSize: 26,
                                fontWeight: FontWeight.w700,
                                color: AppTheme.textPrimary,
                                letterSpacing: -0.6,
                              ),
                            ),
                            if (!_loading && _error == null)
                              Text(
                                'Schuljahr ${AppConfig.currentSchoolYear}',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: AppTheme.textTertiary,
                                  letterSpacing: -0.1,
                                ),
                              ),
                          ],
                        ),
                      ),
                      TopBarActions(service: widget.service),
                    ],
                  ),
                ),
              ),

              // ── Overview Card ────────────────────────────────────────────
              if (!_loading && _error == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
                    child: _OverviewCard(
                      totalHours: _totalHours,
                      excusedHours: _excusedHours,
                      unexcusedHours: _unexcusedHours,
                      absenceRate: _absenceRate,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 10)),

              // ── Content ──────────────────────────────────────────────────
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
                            color: AppTheme.textSecondary,
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
                            child: Icon(
                              CupertinoIcons.exclamationmark_triangle_fill,
                              color: AppTheme.danger,
                              size: 24,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            _error!,
                            style: TextStyle(color: AppTheme.textSecondary, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 18),
                          GestureDetector(
                            onTap: _load,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 24, vertical: 12),
                              decoration: BoxDecoration(
                                color: AppTheme.orange,
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
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Du hattest in diesem Schuljahr keine\neingetragenen Abwesenheiten.',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppTheme.textSecondary,
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
                        return _MonthSection(
                          month: months[i],
                          entries: _grouped[months[i]]!,
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
    );
  }
}

// ── Overview Card ─────────────────────────────────────────────────────────────

class _OverviewCard extends StatelessWidget {
  final int totalHours;
  final int excusedHours;
  final int unexcusedHours;
  final double absenceRate;

  const _OverviewCard({
    required this.totalHours,
    required this.excusedHours,
    required this.unexcusedHours,
    required this.absenceRate,
  });

  Color _rateColor(double rate) => rate > 10
      ? AppTheme.danger
      : rate > 5
          ? AppTheme.warning
          : AppTheme.tint;

  @override
  Widget build(BuildContext context) {
    final excusedFraction =
        totalHours > 0 ? excusedHours / totalHours : 0.0;
    final unexcusedFraction =
        totalHours > 0 ? unexcusedHours / totalHours : 0.0;
    final rateFraction = (absenceRate / 100).clamp(0.0, 1.0);
    final rateColor = _rateColor(absenceRate);

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.35)),
      ),
      child: Column(
        children: [
          // ── Top: ring + numbers ──────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                _RingChart(
                  excusedFraction: excusedFraction,
                  unexcusedFraction: unexcusedFraction,
                  total: totalHours,
                ),
                const SizedBox(width: 22),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _NumberRow(
                        label: 'Fehlstunden gesamt',
                        value: '$totalHours',
                        color: AppTheme.textPrimary,
                        large: true,
                      ),
                      const SizedBox(height: 14),
                      Row(
                        children: [
                          Expanded(
                            child: _MiniStat(
                              label: 'Entschuldigt',
                              value: '$excusedHours',
                              color: AppTheme.tint,
                              icon: CupertinoIcons.checkmark_circle_fill,
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _MiniStat(
                              label: 'Unentsch.',
                              value: '$unexcusedHours',
                              color: unexcusedHours > 0
                                  ? AppTheme.danger
                                  : AppTheme.textTertiary,
                              icon: CupertinoIcons.xmark_circle_fill,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // ── Divider ──────────────────────────────────────────────────
          Divider(
            height: 1,
            color: AppTheme.separator.withValues(alpha: 0.25),
          ),

          // ── Bottom: Fehlquote bar (full school year = 100 %) ─────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'Fehlquote',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${absenceRate.toStringAsFixed(1)} % vom Schuljahr',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: rateColor,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 9),
                // Single bar: filled portion = absenceRate % of full school year
                ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: SizedBox(
                    height: 10,
                    child: LayoutBuilder(
                      builder: (_, constraints) {
                        final w = constraints.maxWidth;
                        final fillW = (w * rateFraction).clamp(0.0, w);
                        return Stack(
                          children: [
                            Container(width: w, color: AppTheme.card),
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
                const SizedBox(height: 8),
                Row(
                  children: [
                    _BarLegend(color: AppTheme.tint, label: '< 5 % Normal'),
                    const SizedBox(width: 14),
                    _BarLegend(color: AppTheme.warning, label: '5–10 % Erhöht'),
                    const SizedBox(width: 14),
                    _BarLegend(color: AppTheme.danger, label: '> 10 % Kritisch'),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingChart extends StatelessWidget {
  final double excusedFraction;
  final double unexcusedFraction;
  final int total;

  const _RingChart({
    required this.excusedFraction,
    required this.unexcusedFraction,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 76,
      height: 76,
      child: CustomPaint(
        painter: _RingPainter(
          excusedFraction: excusedFraction,
          unexcusedFraction: unexcusedFraction,
          bgColor: AppTheme.card,
          excusedColor: AppTheme.tint,
          unexcusedColor: AppTheme.danger,
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$total',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              Text(
                'Std.',
                style: TextStyle(
                  fontSize: 10,
                  color: AppTheme.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double excusedFraction;
  final double unexcusedFraction;
  final Color bgColor;
  final Color excusedColor;
  final Color unexcusedColor;

  const _RingPainter({
    required this.excusedFraction,
    required this.unexcusedFraction,
    required this.bgColor,
    required this.excusedColor,
    required this.unexcusedColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 5;
    const strokeWidth = 7.0;
    const startAngle = -math.pi / 2;

    final bgPaint = Paint()
      ..color = bgColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    if (excusedFraction > 0) {
      final p = Paint()
        ..color = excusedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        excusedFraction * 2 * math.pi,
        false,
        p,
      );
    }
    if (unexcusedFraction > 0) {
      final p = Paint()
        ..color = unexcusedColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle + excusedFraction * 2 * math.pi,
        unexcusedFraction * 2 * math.pi,
        false,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.excusedFraction != excusedFraction ||
      old.unexcusedFraction != unexcusedFraction;
}

class _NumberRow extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool large;

  const _NumberRow({
    required this.label,
    required this.value,
    required this.color,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: large ? 38 : 24,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -1,
            height: 1.0,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textTertiary,
          ),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final IconData icon;

  const _MiniStat({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color,
                  letterSpacing: -0.5,
                  height: 1.0,
                ),
              ),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
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

class _BarLegend extends StatelessWidget {
  final Color color;
  final String label;
  const _BarLegend({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
        ),
      ],
    );
  }
}

// ── Month Section ─────────────────────────────────────────────────────────────

class _MonthSection extends StatelessWidget {
  final String month;
  final List<AbsenceEntry> entries;

  const _MonthSection({required this.month, required this.entries});

  @override
  Widget build(BuildContext context) {
    final monthHours = entries.fold(0, (s, a) => s + a.hours);
    final excusedCount = entries.where((e) => e.isExcused).length;
    final unexcusedCount = entries.length - excusedCount;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Month header
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 14, 0, 10),
            child: Row(
              children: [
                Text(
                  month.toUpperCase(),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textTertiary,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Container(
                    height: 1,
                    color: AppTheme.separator.withValues(alpha: 0.2),
                  ),
                ),
                const SizedBox(width: 8),
                // month summary chips
                if (excusedCount > 0)
                  _MonthChip(
                    label: '$excusedCount ✓',
                    color: AppTheme.tint,
                  ),
                if (unexcusedCount > 0) ...[
                  const SizedBox(width: 4),
                  _MonthChip(
                    label: '$unexcusedCount ✗',
                    color: AppTheme.danger,
                  ),
                ],
                const SizedBox(width: 4),
                _MonthChip(
                  label: '$monthHours Std.',
                  color: AppTheme.textTertiary,
                ),
              ],
            ),
          ),

          // Absence cards
          ...entries.asMap().entries.map((e) => Padding(
                padding: EdgeInsets.only(
                    bottom: e.key < entries.length - 1 ? 8 : 0),
                child: _AbsenceCard(entry: e.value),
              )),
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
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

// ── Absence Card ──────────────────────────────────────────────────────────────

class _AbsenceCard extends StatelessWidget {
  final AbsenceEntry entry;
  const _AbsenceCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    final isExcused = entry.isExcused;
    final accent = isExcused ? AppTheme.tint : AppTheme.danger;

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppTheme.border.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
                    // Row 1: date + status tag + hours
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            entry.dateFormatted,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.3,
                            ),
                          ),
                        ),
                        // Status tag
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isExcused
                                    ? CupertinoIcons.checkmark_circle_fill
                                    : CupertinoIcons.xmark_circle_fill,
                                size: 10,
                                color: accent,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isExcused ? 'Entschuldigt' : 'Unentschuldigt',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: accent,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        // Hours badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: AppTheme.card,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${entry.hours} Std.',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),

                    // Row 2: time (if available)
                    if (entry.timeFormatted.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(CupertinoIcons.clock,
                              size: 12, color: AppTheme.textTertiary),
                          const SizedBox(width: 5),
                          Text(
                            entry.timeFormatted,
                            style: TextStyle(
                              fontSize: 13,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],

                    // Row 3: details (reason, type, note)
                    if (_hasDetails) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppTheme.card,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          children: _buildDetails(),
                        ),
                      ),
                    ],
          ],
        ),
      ),
    );
  }

  bool get _hasDetails =>
      entry.reasonName != null ||
      entry.absenceType != null ||
      entry.note != null ||
      entry.excuseNote != null;

  List<Widget> _buildDetails() {
    final items = <_Detail>[];
    if (entry.reasonName != null)
      items.add(_Detail(CupertinoIcons.tag, 'Grund', entry.reasonName!));
    if (entry.absenceType != null)
      items.add(_Detail(CupertinoIcons.doc_text, 'Art', entry.absenceType!));
    if (entry.note != null)
      items.add(_Detail(CupertinoIcons.pencil, 'Notiz', entry.note!));
    if (entry.excuseNote != null)
      items.add(_Detail(
          CupertinoIcons.checkmark_shield, 'Entschuldigung', entry.excuseNote!));

    return items.asMap().entries.map((e) {
      final isLast = e.key == items.length - 1;
      return Padding(
        padding: EdgeInsets.only(bottom: isLast ? 0 : 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(e.value.icon, size: 12, color: AppTheme.textTertiary),
            const SizedBox(width: 7),
            SizedBox(
              width: 84,
              child: Text(
                e.value.label,
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                ),
              ),
            ),
            Expanded(
              child: Text(
                e.value.value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: AppTheme.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }).toList();
  }
}

class _Detail {
  final IconData icon;
  final String label;
  final String value;
  const _Detail(this.icon, this.label, this.value);
}
