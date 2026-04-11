import 'package:flutter/material.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';

class TimetableScreen extends StatefulWidget {
  final WebUntisService service;
  const TimetableScreen({super.key, required this.service});

  @override
  State<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends State<TimetableScreen> {
  List<TimetableEntry> _entries = [];
  bool _loading = true;
  DateTime _weekStart = DateTime.now();
  final _days = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];

  @override
  void initState() {
    super.initState();
    _weekStart = _getMonday(DateTime.now());
    _load();
  }

  DateTime _getMonday(DateTime d) => d.subtract(Duration(days: d.weekday - 1));

  Future<void> _load() async {
    setState(() => _loading = true);
    final entries = await widget.service.getWeekTimetable(weekStart: _weekStart);
    if (mounted) setState(() { _entries = entries; _loading = false; });
  }

  void _prevWeek() { _weekStart = _weekStart.subtract(const Duration(days: 7)); _load(); }
  void _nextWeek() { _weekStart = _weekStart.add(const Duration(days: 7)); _load(); }

  List<TimetableEntry> _forDay(int dayOffset) {
    final date = _weekStart.add(Duration(days: dayOffset));
    final dateInt = int.parse('${date.year}${date.month.toString().padLeft(2,'0')}${date.day.toString().padLeft(2,'0')}');
    return _entries.where((e) => e.date == dateInt).toList();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Stundenplan', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
                Row(
                  children: [
                    _navBtn(Icons.chevron_left, _prevWeek),
                    const SizedBox(width: 8),
                    Text(
                      'KW ${_weekNumber(_weekStart)}',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                    const SizedBox(width: 8),
                    _navBtn(Icons.chevron_right, _nextWeek),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator(color: AppTheme.accent)))
          else
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                itemCount: 5,
                itemBuilder: (_, i) {
                  final day = _weekStart.add(Duration(days: i));
                  final entries = _forDay(i);
                  return _DaySection(
                    label: _days[i],
                    date: '${day.day}.${day.month}',
                    entries: entries,
                    isToday: _isSameDay(day, DateTime.now()),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  int _weekNumber(DateTime date) {
    final startOfYear = DateTime(date.year, 1, 1);
    final diff = date.difference(startOfYear).inDays;
    return ((diff + startOfYear.weekday) / 7).ceil();
  }

  Widget _navBtn(IconData icon, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.border),
      ),
      child: Icon(icon, size: 18, color: AppTheme.textSecondary),
    ),
  );
}

class _DaySection extends StatelessWidget {
  final String label;
  final String date;
  final List<TimetableEntry> entries;
  final bool isToday;

  const _DaySection({
    required this.label,
    required this.date,
    required this.entries,
    required this.isToday,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isToday ? AppTheme.accent : AppTheme.card,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isToday ? AppTheme.accent : AppTheme.border),
                ),
                child: Text(
                  '$label $date',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isToday ? Colors.white : AppTheme.textSecondary,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (entries.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text('—', style: TextStyle(color: AppTheme.textSecondary.withOpacity(0.4))),
            )
          else
            ...entries.map((e) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.card,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: e.isCancelled ? AppTheme.danger.withOpacity(0.3) : AppTheme.border,
                  ),
                ),
                child: Row(
                  children: [
                    Text(
                      '${e.startFormatted}–${e.endFormatted}',
                      style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary, fontFamily: 'monospace'),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        e.subjectName,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: e.isCancelled ? AppTheme.danger : AppTheme.textPrimary,
                          decoration: e.isCancelled ? TextDecoration.lineThrough : null,
                        ),
                      ),
                    ),
                    if (e.roomName.isNotEmpty)
                      Text(e.roomName, style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
                  ],
                ),
              ),
            )),
        ],
      ),
    );
  }
}