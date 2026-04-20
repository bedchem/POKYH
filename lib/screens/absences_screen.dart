import 'dart:io';
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
      setState(() {
        _absences = cached;
        _loading = false;
      });
      _refreshInBackground();
      return;
    }

    setState(() {
      _loading = _absences.isEmpty;
      _error = null;
    });
    try {
      final absences = await widget.service.getAbsences(
        forceRefresh: forceRefresh,
      );
      if (mounted) setState(() { _absences = absences; _loading = false; });
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

  // Fehlquote: absent hours / estimated total school hours this year × 100
  double get _absenceRate {
    if (_totalHours == 0) return 0;
    final now = DateTime.now();
    final startYear = now.month >= 9 ? now.year : now.year - 1;
    final schoolYearStart = DateTime(startYear, 9, 1);
    final elapsed = now.difference(schoolYearStart).inDays;
    // Estimate: 5 school days / week × 7 lessons / day, minus ~30% holidays/weekends
    final schoolDays = (elapsed * 5 / 7 * 0.85).round();
    final estimatedTotal = schoolDays * 7;
    if (estimatedTotal <= 0) return 0;
    return (_totalHours / estimatedTotal * 100).clamp(0, 100);
  }

  // Group absences by month label
  Map<String, List<AbsenceEntry>> get _grouped {
    final result = <String, List<AbsenceEntry>>{};
    for (final a in _absences) {
      final dt = a.startDateTime;
      final key =
          '${AppConfig.monthLabels[dt.month - 1]} ${dt.year}';
      result.putIfAbsent(key, () => []).add(a);
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
                                color: AppTheme.surface,
                                borderRadius: BorderRadius.circular(10),
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
                          const SizedBox(width: 12),
                          Text(
                            'Abwesenheiten',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const Spacer(),
                          TopBarActions(service: widget.service),
                        ],
                      ),
                      if (!_loading && _error == null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4, left: 46),
                          child: Text(
                            'Schuljahr ${AppConfig.currentSchoolYear}',
                            style: TextStyle(
                              fontSize: 14,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              // ── Stats Card ──
              if (!_loading && _error == null)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: _StatsCard(
                      totalHours: _totalHours,
                      excusedHours: _excusedHours,
                      unexcusedHours: _unexcusedHours,
                      absenceRate: _absenceRate,
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
                          _error!,
                          style: TextStyle(color: AppTheme.textSecondary),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 14),
                        CupertinoButton(
                          color: AppTheme.orange,
                          borderRadius: BorderRadius.circular(10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          onPressed: _load,
                          child: const Text(
                            'Erneut versuchen',
                            style: TextStyle(fontSize: 14),
                          ),
                        ),
                      ],
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
                        Icon(
                          CupertinoIcons.checkmark_seal_fill,
                          size: 44,
                          color: AppTheme.tint,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Keine Abwesenheiten',
                          style: TextStyle(
                            color: AppTheme.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (_, i) {
                        final months = _grouped.keys.toList();
                        final month = months[i];
                        final entries = _grouped[month]!;
                        return _MonthSection(
                          month: month,
                          entries: entries,
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

// ── Stats Card ────────────────────────────────────────────────────────────────

class _StatsCard extends StatelessWidget {
  final int totalHours;
  final int excusedHours;
  final int unexcusedHours;
  final double absenceRate;

  const _StatsCard({
    required this.totalHours,
    required this.excusedHours,
    required this.unexcusedHours,
    required this.absenceRate,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: AppTheme.orange.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _StatItem(
                  label: 'Fehlstunden',
                  value: '$totalHours',
                  color: AppTheme.orange,
                  large: true,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'Entschuldigt',
                  value: '$excusedHours',
                  color: AppTheme.tint,
                ),
              ),
              Expanded(
                child: _StatItem(
                  label: 'Unentschuldigt',
                  value: '$unexcusedHours',
                  color: AppTheme.danger,
                ),
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
                  color: AppTheme.textSecondary,
                ),
              ),
              const Spacer(),
              Text(
                '${absenceRate.toStringAsFixed(1)} %',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: absenceRate > 10
                      ? AppTheme.danger
                      : absenceRate > 5
                          ? AppTheme.warning
                          : AppTheme.tint,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (absenceRate / 100).clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: AppTheme.card,
              valueColor: AlwaysStoppedAnimation<Color>(
                absenceRate > 10
                    ? AppTheme.danger
                    : absenceRate > 5
                        ? AppTheme.warning
                        : AppTheme.tint,
              ),
            ),
          ),
          if (totalHours > 0) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _PillBar(
                    label: 'E',
                    color: AppTheme.tint,
                    fraction: totalHours > 0 ? excusedHours / totalHours : 0,
                    value: excusedHours,
                    total: totalHours,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _PillBar(
                    label: 'U',
                    color: AppTheme.danger,
                    fraction: totalHours > 0 ? unexcusedHours / totalHours : 0,
                    value: unexcusedHours,
                    total: totalHours,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final bool large;

  const _StatItem({
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
            fontSize: large ? 36 : 26,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: -1,
          ),
        ),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: AppTheme.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _PillBar extends StatelessWidget {
  final String label;
  final Color color;
  final double fraction;
  final int value;
  final int total;

  const _PillBar({
    required this.label,
    required this.color,
    required this.fraction,
    required this.value,
    required this.total,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (fraction * 100).round();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label == 'E' ? 'Entschuldigt' : 'Unentsch.',
            style: TextStyle(
              fontSize: 11,
              color: AppTheme.textSecondary,
            ),
          ),
          const Spacer(),
          Text(
            '$pct %',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
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
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Row(
              children: [
                Text(
                  month,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                    letterSpacing: 0.3,
                  ),
                ),
                const Spacer(),
                Text(
                  '$monthHours Std.',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppTheme.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.surface,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: List.generate(entries.length, (i) {
                final isLast = i == entries.length - 1;
                return _AbsenceRow(entry: entries[i], isLast: isLast);
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Absence Row ───────────────────────────────────────────────────────────────

class _AbsenceRow extends StatelessWidget {
  final AbsenceEntry entry;
  final bool isLast;

  const _AbsenceRow({required this.entry, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final color = entry.isExcused ? AppTheme.tint : AppTheme.danger;
    final statusText = entry.isExcused ? 'Entschuldigt' : 'Unentschuldigt';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: IntrinsicHeight(
            child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Left accent bar
              Container(
                width: 3,
                constraints: const BoxConstraints(minHeight: 48),
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Row 1: date + hours badge ──
                    Row(
                      children: [
                        Text(
                          entry.dateFormatted,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
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
                    const SizedBox(height: 8),

                    // ── Details grid ──
                    _DetailTable(entry: entry),

                    const SizedBox(height: 10),

                    // ── Status chip ──
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: color.withValues(alpha: 0.25),
                        ),
                      ),
                      child: Text(
                        statusText,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            ),
          ),
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 33,
            color: AppTheme.separator.withValues(alpha: 0.4),
          ),
      ],
    );
  }
}

// ── Detail Table ──────────────────────────────────────────────────────────────

class _DetailTable extends StatelessWidget {
  final AbsenceEntry entry;
  const _DetailTable({required this.entry});

  @override
  Widget build(BuildContext context) {
    final rows = <_DetailRow>[];

    if (entry.timeFormatted.isNotEmpty) {
      rows.add(_DetailRow(
        icon: CupertinoIcons.clock,
        label: 'Uhrzeit',
        value: entry.timeFormatted,
      ));
    }
    if (entry.reasonName != null) {
      rows.add(_DetailRow(
        icon: CupertinoIcons.tag,
        label: 'Grund',
        value: entry.reasonName!,
      ));
    }
    if (entry.absenceType != null) {
      rows.add(_DetailRow(
        icon: CupertinoIcons.doc_text,
        label: 'Art',
        value: entry.absenceType!,
      ));
    }
    if (entry.note != null) {
      rows.add(_DetailRow(
        icon: CupertinoIcons.pencil,
        label: 'Notiz',
        value: entry.note!,
      ));
    }
    if (entry.excuseNote != null) {
      rows.add(_DetailRow(
        icon: CupertinoIcons.checkmark_shield,
        label: 'Entschuldigungstext',
        value: entry.excuseNote!,
      ));
    }

    if (rows.isEmpty) return const SizedBox.shrink();

    return Column(
      children: List.generate(rows.length, (i) {
        final r = rows[i];
        return Padding(
          padding: EdgeInsets.only(bottom: i < rows.length - 1 ? 6 : 0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(r.icon, size: 13, color: AppTheme.textTertiary),
              const SizedBox(width: 6),
              SizedBox(
                width: 90,
                child: Text(
                  r.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  r.value,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

class _DetailRow {
  final IconData icon;
  final String label;
  final String value;
  const _DetailRow({required this.icon, required this.label, required this.value});
}
