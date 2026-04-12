import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
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

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final grades = await widget.service.getAllGrades();
      if (mounted) setState(() { _subjects = grades; _loading = false; });
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

  double? get _totalAverage {
    final avgs = _subjects.map((s) => s.average).whereType<double>().toList();
    if (avgs.isEmpty) return null;
    return avgs.reduce((a, b) => a + b) / avgs.length;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
                  const Text('Noten',
                      style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary, letterSpacing: -0.5)),
                  if (!_loading && _error == null && _subjects.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${_subjects.length} F\u00e4cher \u00b7 Schuljahr 2025/2026',
                        style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // ── Overview card ──
          if (!_loading && _error == null && _subjects.isNotEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: _OverviewCard(
                  average: _totalAverage,
                  subjects: _subjects,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // ── Content ──
          if (_loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CupertinoActivityIndicator(radius: 14),
                    SizedBox(height: 14),
                    Text('Noten werden geladen\u2026',
                        style: TextStyle(color: AppTheme.textSecondary, fontSize: 14)),
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
            )
          else if (_subjects.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: Text('Keine Noten vorhanden',
                    style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
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
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════

class _OverviewCard extends StatelessWidget {
  final double? average;
  final List<SubjectGrades> subjects;
  const _OverviewCard({required this.average, required this.subjects});

  @override
  Widget build(BuildContext context) {
    final totalGrades = subjects.fold<int>(0, (s, e) => s + e.grades.length);
    final positive = subjects.fold<int>(0, (s, e) => s + e.positiveCount);
    final negative = subjects.fold<int>(0, (s, e) => s + e.negativeCount);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppTheme.accent.withValues(alpha: 0.15),
            AppTheme.accentSoft.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          // Average
          if (average != null)
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: _gradeColor(average!).withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: _gradeColor(average!).withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  average!.toStringAsFixed(1),
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: _gradeColor(average!),
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
                const Text('Gesamtdurchschnitt',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary)),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _StatPill(label: '$totalGrades', sub: 'Noten', color: AppTheme.accent),
                    const SizedBox(width: 8),
                    _StatPill(label: '$positive', sub: 'positiv', color: AppTheme.success),
                    const SizedBox(width: 8),
                    _StatPill(label: '$negative', sub: 'negativ', color: AppTheme.danger),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _gradeColor(double v) {
    if (v >= 9) return AppTheme.success;
    if (v >= 7) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return AppTheme.orange;
    return AppTheme.danger;
  }
}

class _StatPill extends StatelessWidget {
  final String label;
  final String sub;
  final Color color;
  const _StatPill({required this.label, required this.sub, required this.color});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        Text(sub, style: const TextStyle(fontSize: 10, color: AppTheme.textTertiary)),
      ],
    );
  }
}

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
    if (v >= 7) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return AppTheme.orange;
    return AppTheme.danger;
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
          color: AppTheme.surface,
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
                  // Subject color dot
                  Container(
                    width: 10, height: 10,
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.subject.teacherName} \u00b7 ${widget.subject.grades.length} Noten',
                          style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                        ),
                      ],
                    ),
                  ),

                  // Average pill
                  if (avg != null)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _gradeColor(avg).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: _gradeColor(avg).withValues(alpha: 0.3)),
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
                    child: const Icon(CupertinoIcons.chevron_down,
                        size: 14, color: AppTheme.textTertiary),
                  ),
                ],
              ),
            ),

            // Expanded grades
            AnimatedCrossFade(
              duration: const Duration(milliseconds: 250),
              crossFadeState: _expanded
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: Column(
                children: [
                  Divider(color: AppTheme.border.withValues(alpha: 0.5), height: 1,
                      indent: 14, endIndent: 14),
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
                                width: 40,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 4),
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
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  g.examType.isNotEmpty
                                      ? g.examType
                                      : (g.text.isNotEmpty ? g.text : '\u2014'),
                                  style: const TextStyle(fontSize: 14,
                                      color: AppTheme.textSecondary),
                                ),
                              ),
                              Text(
                                g.dateFormatted,
                                style: const TextStyle(fontSize: 12,
                                    color: AppTheme.textTertiary,
                                    fontFeatures: [FontFeature.tabularFigures()]),
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
