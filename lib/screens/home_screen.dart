import 'package:flutter/material.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'timetable_screen.dart';
import 'grades_screen.dart';
import 'login_screen.dart';

class HomeScreen extends StatefulWidget {
  final WebUntisService service;
  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  late final List<Widget> _screens;

  @override
  void initState() {
    super.initState();
    _screens = [
      DashboardTab(service: widget.service),
      TimetableScreen(service: widget.service),
      GradesScreen(service: widget.service),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(index: _tab, children: _screens),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppTheme.border)),
        ),
        child: BottomNavigationBar(
          currentIndex: _tab,
          onTap: (i) => setState(() => _tab = i),
          backgroundColor: AppTheme.surface,
          selectedItemColor: AppTheme.accent,
          unselectedItemColor: AppTheme.textSecondary,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.grid_view_rounded, size: 22), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.calendar_today_rounded, size: 22), label: 'Stundenplan'),
            BottomNavigationBarItem(icon: Icon(Icons.bar_chart_rounded, size: 22), label: 'Noten'),
          ],
        ),
      ),
    );
  }
}

// ── DASHBOARD TAB ─────────────────────────────────────────────────────────────

class DashboardTab extends StatefulWidget {
  final WebUntisService service;
  const DashboardTab({super.key, required this.service});

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  List<TimetableEntry> _today = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final entries = await widget.service.getTimetable();
    if (mounted) setState(() { _today = entries; _loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
    final months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun', 'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('pockyh', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: AppTheme.textPrimary, letterSpacing: -0.5)),
                    Text('${days[now.weekday - 1]}, ${now.day}. ${months[now.month - 1]}',
                        style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  ],
                ),
GestureDetector(
  onTap: () async {
    await widget.service.logout();
    if (context.mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  },
  child: Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: AppTheme.border),
    ),
    child: const Text('logout', style: TextStyle(fontSize: 12, color: AppTheme.textSecondary, letterSpacing: 0.5)),
  ),
),
              ],
            ),
            const SizedBox(height: 28),

            // Today
            const Text('HEUTE', style: TextStyle(fontSize: 11, color: AppTheme.textSecondary, letterSpacing: 2, fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),

            if (_loading)
              const Center(child: CircularProgressIndicator(color: AppTheme.accent))
            else if (_today.isEmpty)
              _emptyCard('Kein Unterricht heute 🎉')
            else
              ..._today.map((e) => _TimetableCard(entry: e)),
          ],
        ),
      ),
    );
  }

  Widget _emptyCard(String msg) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: AppTheme.card,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppTheme.border),
    ),
    child: Text(msg, style: const TextStyle(color: AppTheme.textSecondary)),
  );
}

class _TimetableCard extends StatelessWidget {
  final TimetableEntry entry;
  const _TimetableCard({required this.entry});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: entry.isCancelled ? AppTheme.danger.withOpacity(0.4) : AppTheme.border,
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 40,
            decoration: BoxDecoration(
              color: entry.isCancelled ? AppTheme.danger : AppTheme.accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.subjectLong.isNotEmpty ? entry.subjectLong : entry.subjectName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: entry.isCancelled ? AppTheme.danger : AppTheme.textPrimary,
                    decoration: entry.isCancelled ? TextDecoration.lineThrough : null,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.teacherName}${entry.roomName.isNotEmpty ? ' · ${entry.roomName}' : ''}',
                  style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
          Text(
            '${entry.startFormatted}\n${entry.endFormatted}',
            textAlign: TextAlign.right,
            style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
          ),
        ],
      ),
    );
  }
}