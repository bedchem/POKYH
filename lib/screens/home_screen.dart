import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/webuntis_service.dart';
import '../theme/app_theme.dart';
import 'timetable_screen.dart' show TimetableScreen, TimetableScreenState;
import 'grades_screen.dart';
import 'mensa_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';

class HomeScreen extends StatefulWidget {
  final WebUntisService service;
  const HomeScreen({super.key, required this.service});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  late final List<Widget> _screens;
  late GlobalKey<TimetableScreenState> _timetableKey;
  late final MensaScreenController _mensaController;
  int _unreadMessages = 0;

  @override
  void initState() {
    super.initState();
    _timetableKey = TimetableScreen.createKey();
    _mensaController = MensaScreenController();
    NotificationService().onNewMessages = _showNewMessageBanner;
    NotificationService().startPolling(widget.service);
    // Trigger update check after the first frame so the UI is fully visible.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 900), _checkForUpdate);
      _fetchUnreadCount();
    });
    _screens = [
      _DashboardTab(
        service: widget.service,
        onMensaTap: _showMensaTab,
        onExamTap: (exam) {
          if (exam == null) return;
          setState(() => _tab = 1);
          final now = DateTime.now();
          final examDate = DateTime(
            int.parse(exam.entry.date.toString().substring(0, 4)),
            int.parse(exam.entry.date.toString().substring(4, 6)),
            int.parse(exam.entry.date.toString().substring(6, 8)),
          );
          final thisMonday = DateTime(
            now.year,
            now.month,
            now.day,
          ).subtract(Duration(days: now.weekday - 1));
          final weekOffset = examDate.difference(thisMonday).inDays ~/ 7;
          final dayIndex = examDate.weekday - 1;
          Future.delayed(const Duration(milliseconds: 120), () {
            final timetableState = _timetableKey.currentState;
            if (timetableState != null) {
              timetableState.jumpToWeekAndDay(
                weekOffset: weekOffset,
                dayIndex: dayIndex,
                entry: exam.entry,
                replacement: null,
              );
            }
          });
        },
      ),
      TimetableScreen(service: widget.service, key: _timetableKey),
      GradesScreen(service: widget.service),
      MensaScreen(controller: _mensaController),
    ];
  }

  void _showMensaTab() {
    _mensaController.scrollToTop();
    setState(() => _tab = 3);
  }

  Future<void> _checkForUpdate() async {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    try {
      await UpdateService.checkForUpdate(
        context,
        source: UpdateCheckSource.homeAuto,
      );
    } catch (_) {}
  }

  Future<void> _logout() async {
    NotificationService().stopPolling();
    await widget.service.logout();
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
    );
  }

  void _showNewMessageBanner(int count, String? subject) {
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    final text = count == 1
        ? 'Neue Mitteilung: ${subject ?? ''}'
        : '$count neue Mitteilungen';

    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(
              CupertinoIcons.bell_fill,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(fontWeight: FontWeight.w600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: AppTheme.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Anzeigen',
          textColor: Colors.white,
          onPressed: () {
            Navigator.push(
              context,
              CupertinoPageRoute(
                builder: (_) => MessagesScreen(service: widget.service),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _fetchUnreadCount() async {
    try {
      await widget.service.getMessages();
      if (mounted) {
        setState(() => _unreadMessages = widget.service.unreadMessageCount);
      }
    } catch (_) {}
  }

  void _openMessages() async {
    await Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => MessagesScreen(service: widget.service),
      ),
    );
    // Refresh unread count when returning
    if (mounted) {
      setState(() => _unreadMessages = widget.service.unreadMessageCount);
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) =>
            ProfileScreen(service: widget.service, onLogout: _logout),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bg,
      body: Stack(
        children: [
          IndexedStack(index: _tab, children: _screens),
          Positioned(
            top: MediaQuery.of(context).padding.top + 12,
            right: 16,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  onTap: _openMessages,
                  child: _MessageBadgeIcon(unreadCount: _unreadMessages),
                ),
                const SizedBox(width: 10),
                GestureDetector(
                  onTap: _openProfile,
                  child: _SmallProfileAvatar(service: widget.service),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border(
            top: BorderSide(
              color: AppTheme.border.withValues(alpha: 0.5),
              width: 0.5,
            ),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 5, bottom: 2),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _TabItem(
                  icon: CupertinoIcons.house_fill,
                  label: 'Home',
                  active: _tab == 0,
                  onTap: () => setState(() => _tab = 0),
                ),
                _TabItem(
                  icon: CupertinoIcons.calendar,
                  label: 'Stundenplan',
                  active: _tab == 1,
                  onTap: () {
                    if (_tab == 1) {
                      final timetableState = _timetableKey.currentState;
                      if (timetableState != null) {
                        final now = DateTime.now();
                        final todayIndex = now.weekday <= 5
                            ? now.weekday - 1
                            : null;
                        timetableState.jumpToWeekAndDay(
                          weekOffset: 0,
                          dayIndex: todayIndex,
                        );
                      }
                    }
                    setState(() => _tab = 1);
                  },
                ),
                _TabItem(
                  icon: CupertinoIcons.chart_bar_fill,
                  label: 'Noten',
                  active: _tab == 2,
                  onTap: () => setState(() => _tab = 2),
                ),
                _TabItem(
                  icon: CupertinoIcons.flame_fill,
                  label: 'Mensa',
                  active: _tab == 3,
                  onTap: _showMensaTab,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ── Small Profile Avatar ──────────────────────────────────────────────────────

class _SmallProfileAvatar extends StatefulWidget {
  final WebUntisService service;
  const _SmallProfileAvatar({required this.service});

  @override
  State<_SmallProfileAvatar> createState() => _SmallProfileAvatarState();
}

class _SmallProfileAvatarState extends State<_SmallProfileAvatar> {
  @override
  void initState() {
    super.initState();
    if (!widget.service.profileImageFetched) {
      widget.service.fetchProfileImage().then((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bytes = widget.service.profileImageBytes;
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 7,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: bytes != null
          ? Image.memory(
              bytes,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => _fallback(),
            )
          : _fallback(),
    );
  }

  Widget _fallback() => Center(
    child: Icon(
      CupertinoIcons.person_fill,
      size: 16,
      color: AppTheme.textSecondary,
    ),
  );
}

// ── Message Badge Icon ───────────────────────────────────────────────────────

class _MessageBadgeIcon extends StatelessWidget {
  final int unreadCount;
  const _MessageBadgeIcon({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 32,
      height: 32,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.surface,
              border: Border.all(color: AppTheme.border.withValues(alpha: 0.4)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 7,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Center(
              child: Icon(
                CupertinoIcons.bell_fill,
                size: 15,
                color: AppTheme.textSecondary,
              ),
            ),
          ),
          if (unreadCount > 0)
            Positioned(
              top: -3,
              right: -3,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                decoration: BoxDecoration(
                  color: AppTheme.danger,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppTheme.bg, width: 1.5),
                ),
                child: Center(
                  child: Text(
                    unreadCount > 99 ? '99+' : '$unreadCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ── Tab Item ──────────────────────────────────────────────────────────────────

class _TabItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _TabItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 20,
              color: active ? AppTheme.accent : AppTheme.textTertiary,
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: TextStyle(
                fontSize: 9,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: active ? AppTheme.accent : AppTheme.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MODELS
// ═══════════════════════════════════════════════════════════════════════════════

class _NextExam {
  final TimetableEntry entry;
  final String label;
  final bool isToday;
  final int daysUntil;
  const _NextExam({
    required this.entry,
    required this.label,
    required this.isToday,
    required this.daysUntil,
  });
}

class _RecentGrade {
  final String subject;
  final double value;
  final int date;
  final String type;
  const _RecentGrade({
    required this.subject,
    required this.value,
    required this.date,
    required this.type,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CARD SECTION ENUM + PERSISTENCE
// ═══════════════════════════════════════════════════════════════════════════════

enum _CardSection { weekOverview, examBanner, infoRow, mensa }

const _kCardOrderKey = 'dashboard_card_order_v1';

final _defaultOrder = [
  _CardSection.weekOverview,
  _CardSection.examBanner,
  _CardSection.infoRow,
  _CardSection.mensa,
];

List<_CardSection> _orderFromStrings(List<String> saved) {
  try {
    final result = saved
        .map((s) => _CardSection.values.firstWhere((e) => e.name == s))
        .toList();
    for (final s in _CardSection.values) {
      if (!result.contains(s)) result.add(s);
    }
    return result;
  } catch (_) {
    return List.from(_defaultOrder);
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  DASHBOARD TAB
// ═══════════════════════════════════════════════════════════════════════════════

class _DashboardTab extends StatefulWidget {
  final WebUntisService service;
  final VoidCallback onMensaTap;
  final void Function(_NextExam?)? onExamTap;
  const _DashboardTab({
    required this.service,
    required this.onMensaTap,
    this.onExamTap,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab>
    with SingleTickerProviderStateMixin {
  List<TimetableEntry> _today = [];
  List<TimetableEntry> _allWeek = [];
  bool _loadingTimetable = true;
  String? _errorTimetable;

  List<_RecentGrade> _recentGrades = [];
  double? _weekAverage;
  bool _loadingGrades = true;

  String? _mensaToday;
  String? _mensaCategory;
  bool _loadingMensa = true;

  late AnimationController _fadeController;

  List<_CardSection> _cardOrder = List.from(_defaultOrder);

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _loadCardOrder().then((_) => _load());
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadCardOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getStringList(_kCardOrderKey);
      if (saved != null && saved.isNotEmpty && mounted) {
        setState(() => _cardOrder = _orderFromStrings(saved));
      }
    } catch (_) {}
  }

  Future<void> _saveCardOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        _kCardOrderKey,
        _cardOrder.map((e) => e.name).toList(),
      );
    } catch (_) {}
  }

  Future<void> _load() async {
    // Show cached data immediately so the screen isn't blank while fetching.
    _applyGradesCache(widget.service.cachedGrades);
    final cachedWeek = widget.service.getCachedWeek(_getThisMonday());
    if (cachedWeek != null) _applyTimetableCache(cachedWeek);

    setState(() {
      _loadingTimetable = cachedWeek == null;
      _loadingGrades = widget.service.cachedGrades == null;
      _loadingMensa = true;
      _errorTimetable = null;
    });

    _fadeController.reset();
    await Future.wait([_loadTimetable(), _loadGrades(), _loadMensa()]);
    if (mounted) _fadeController.forward();
  }

  DateTime _getThisMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    return today.subtract(Duration(days: today.weekday - 1));
  }

  void _applyTimetableCache(List<TimetableEntry> allWeek) {
    final now = DateTime.now();
    final todayInt = _dateInt(now);
    _allWeek = allWeek;
    _today = allWeek.where((e) => e.date == todayInt).toList();
    _loadingTimetable = false;
  }

  void _applyGradesCache(List<SubjectGrades>? subjects) {
    if (subjects == null) return;
    final allGrades = <_RecentGrade>[];
    double sum = 0;
    int count = 0;
    for (final subject in subjects) {
      for (final grade in subject.grades) {
        if (grade.markDisplayValue <= 0) continue;
        allGrades.add(
          _RecentGrade(
            subject: subject.subjectName,
            value: grade.markDisplayValue,
            date: grade.date,
            type: grade.examType,
          ),
        );
        sum += grade.markDisplayValue;
        count++;
      }
    }
    allGrades.sort((a, b) => b.date.compareTo(a.date));
    _recentGrades = allGrades.take(3).toList();
    _weekAverage = count > 0 ? sum / count : null;
    _loadingGrades = false;
  }

  Future<void> _loadTimetable() async {
    try {
      final now = DateTime.now();
      final allWeek = await widget.service.getWeekTimetable();
      final todayInt = _dateInt(now);
      if (mounted) {
        setState(() {
          _allWeek = allWeek;
          _today = allWeek.where((e) => e.date == todayInt).toList();
          _loadingTimetable = false;
        });
      }
    } on WebUntisException catch (e) {
      if (mounted) {
        setState(() {
          _errorTimetable = e.message;
          _loadingTimetable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorTimetable = '$e';
          _loadingTimetable = false;
        });
      }
    }
  }

  Future<void> _loadGrades() async {
    try {
      final subjects = await widget.service.getAllGrades();
      if (mounted) setState(() => _applyGradesCache(subjects));
    } catch (_) {
      if (mounted) setState(() => _loadingGrades = false);
    }
  }

  Future<void> _loadMensa() async {
    try {
      final now = DateTime.now();
      final todayStr =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final response = await http
          .get(Uri.parse(AppConfig.mensaApiUrl))
          .timeout(AppConfig.mensaTimeout);

      if (response.statusCode != 200) {
        if (mounted) setState(() => _loadingMensa = false);
        return;
      }

      final json = jsonDecode(response.body);
      List<dynamic> dishes = [];
      if (json is Map) {
        final menu = json['menu'];
        if (menu is Map) {
          dishes = (menu['dishes'] as List?) ?? [];
        } else if (menu is List) {
          dishes = menu;
        } else {
          dishes = (json['dishes'] as List?) ?? [];
        }
      } else if (json is List) {
        dishes = json;
      }

      final todayDishes = dishes.where((d) => d['date'] == todayStr).toList();
      if (!mounted) return;

      if (todayDishes.isEmpty) {
        setState(() {
          _mensaToday = null;
          _loadingMensa = false;
        });
        return;
      }

      final main = todayDishes.firstWhere(
        (d) => (d['category'] ?? '').toString().toLowerCase().contains('haupt'),
        orElse: () => todayDishes.first,
      );

      String name = 'Unbekanntes Gericht';
      final nameField = main['name'];
      if (nameField is Map) {
        name = (nameField['de'] ?? nameField.values.first ?? name).toString();
      } else if (nameField is String) {
        name = nameField;
      }

      String? category;
      final catField = main['category'];
      if (catField is String && catField.isNotEmpty) category = catField;

      setState(() {
        _mensaToday = name;
        _mensaCategory = category;
        _loadingMensa = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMensa = false);
    }
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  int _dateInt(DateTime d) => int.parse(
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
  );

  String? _getSchoolEnd() {
    if (_today.isEmpty) return null;
    final last = _today.last;
    final h = last.endTime ~/ 100;
    final m = last.endTime % 100;
    return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
  }

  int? _minsUntilEnd(DateTime now) {
    if (_today.isEmpty) return null;
    final last = _today.last;
    final endMins = (last.endTime ~/ 100) * 60 + (last.endTime % 100);
    final nowMins = now.hour * 60 + now.minute;
    if (endMins <= nowMins) return null;
    return endMins - nowMins;
  }

  _NextExam? _getNextExam(DateTime now) {
    final todayInt = _dateInt(now);
    final nowMins = now.hour * 60 + now.minute;
    final exams =
        _allWeek.where((e) {
          if (!e.isExam) return false;
          if (e.date > todayInt) return true;
          if (e.date < todayInt) return false;
          // Same day: skip exams whose lesson time has already passed
          final endMins = (e.endTime ~/ 100) * 60 + (e.endTime % 100);
          return endMins > nowMins;
        }).toList()..sort(
          (a, b) => a.date == b.date
              ? a.startTime.compareTo(b.startTime)
              : a.date.compareTo(b.date),
        );
    if (exams.isEmpty) return null;
    final e = exams.first;
    final d = e.date.toString();
    final examDate = DateTime(
      int.parse(d.substring(0, 4)),
      int.parse(d.substring(4, 6)),
      int.parse(d.substring(6, 8)),
    );
    final diff = examDate
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    String label;
    if (diff == 0) {
      label = 'Heute';
    } else if (diff == 1) {
      label = 'Morgen';
    } else {
      const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      label = 'in $diff Tagen (${wd[examDate.weekday - 1]})';
    }
    return _NextExam(
      entry: e,
      label: label,
      isToday: diff == 0,
      daysUntil: diff,
    );
  }

  // ── Card content builders ──────────────────────────────────────────────────

  Widget? _cardContent(_CardSection section, DateTime now) {
    final nextExam = _loadingTimetable ? null : _getNextExam(now);
    final schoolEnd = _getSchoolEnd();
    final minsUntilEnd = _minsUntilEnd(now);

    switch (section) {
      case _CardSection.weekOverview:
        if (_loadingTimetable && _allWeek.isEmpty) {
          return const _LoadingCard();
        }
        if (_allWeek.isEmpty) return null;
        return _WeekOverviewCard(
          allWeek: _allWeek,
          now: now,
          service: widget.service,
        );

      case _CardSection.examBanner:
        if (_loadingTimetable && _allWeek.isEmpty) return null;
        if (_errorTimetable != null) return null;
        return GestureDetector(
          onTap: () => widget.onExamTap?.call(nextExam),
          child: _ExamBanner(nextExam: nextExam),
        );

      case _CardSection.infoRow:
        if (_loadingTimetable && _today.isEmpty) return const _LoadingCard();
        if (_errorTimetable != null) {
          return _ErrorCard(message: _errorTimetable!, onRetry: _load);
        }
        if (_today.isEmpty) return null;
        return IntrinsicHeight(
          child: Row(
            children: [
              Expanded(
                child: _TimeInfoCard(
                  icon: CupertinoIcons.flag_fill,
                  label: 'Schulende',
                  value: schoolEnd ?? '—',
                  sub: minsUntilEnd != null
                      ? 'noch ${_fmtDuration(minsUntilEnd)}'
                      : 'vorbei',
                  color: minsUntilEnd != null
                      ? AppTheme.accent
                      : AppTheme.textTertiary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RecentGradesCard(
                  grades: _recentGrades,
                  average: _weekAverage,
                  loading: _loadingGrades,
                ),
              ),
            ],
          ),
        );

      case _CardSection.mensa:
        return GestureDetector(
          onTap: widget.onMensaTap,
          child: _MensaPreviewCard(
            dish: _mensaToday,
            category: _mensaCategory,
            loading: _loadingMensa,
          ),
        );
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      // Get the visible list to map indices correctly
      final now = DateTime.now();
      final visible = _cardOrder
          .where((s) => _cardContent(s, now) != null)
          .toList();

      final movedSection = visible[oldIndex];

      // Remove from full order
      _cardOrder.remove(movedSection);

      // Find insertion point in full order
      // newIndex refers to position in the visible list after removal
      final newVisible = _cardOrder
          .where((s) => _cardContent(s, now) != null)
          .toList();

      if (newIndex >= newVisible.length) {
        // Insert after last visible item
        final lastVisible = newVisible.isNotEmpty ? newVisible.last : null;
        if (lastVisible == null) {
          _cardOrder.add(movedSection);
        } else {
          final insertAfter = _cardOrder.lastIndexOf(lastVisible);
          _cardOrder.insert(insertAfter + 1, movedSection);
        }
      } else {
        final targetSection = newVisible[newIndex];
        final insertAt = _cardOrder.indexOf(targetSection);
        _cardOrder.insert(insertAt, movedSection);
      }
    });
    _saveCardOrder();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();

    // Build the visible list of (section, widget) pairs
    final visibleCards = _cardOrder
        .map((s) => (section: s, content: _cardContent(s, now)))
        .where((pair) => pair.content != null)
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: _load,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 52, 0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      'Home',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 10)),

            // Reorderable card list
            SliverToBoxAdapter(
              child: _CardReorderList(
                cards: visibleCards
                    .map(
                      (p) => _CardEntry(
                        key: ValueKey(p.section.name),
                        section: p.section,
                        child: p.content!,
                      ),
                    )
                    .toList(),
                onReorder: _onReorder,
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ],
        ),
      ),
    );
  }

  String _fmtDuration(int mins) {
    if (mins < 60) return '${mins}min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CARD ENTRY MODEL
// ═══════════════════════════════════════════════════════════════════════════════

class _CardEntry {
  final Key key;
  final _CardSection section;
  final Widget child;
  const _CardEntry({
    required this.key,
    required this.section,
    required this.child,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CARD REORDER LIST  –  robust drag with correct index math
// ═══════════════════════════════════════════════════════════════════════════════

class _CardReorderList extends StatefulWidget {
  final List<_CardEntry> cards;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _CardReorderList({required this.cards, required this.onReorder});

  @override
  State<_CardReorderList> createState() => _CardReorderListState();
}

class _CardReorderListState extends State<_CardReorderList> {
  int? _draggingIndex;
  int? _hoverIndex;

  void _startDrag(int index) {
    HapticFeedback.mediumImpact();
    setState(() {
      _draggingIndex = index;
      _hoverIndex = null;
    });
  }

  void _endDrag() {
    setState(() {
      _draggingIndex = null;
      _hoverIndex = null;
    });
  }

  void _updateHover(int index) {
    if (_hoverIndex != index) {
      setState(() => _hoverIndex = index);
    }
  }

  void _clearHover() {
    if (_hoverIndex != null) {
      setState(() => _hoverIndex = null);
    }
  }

  void _drop(int fromIndex, int toIndex) {
    _endDrag();
    if (fromIndex != toIndex) {
      widget.onReorder(fromIndex, toIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: List.generate(widget.cards.length, (index) {
        final entry = widget.cards[index];
        final isDraggingThis = _draggingIndex == index;

        return Padding(
          key: entry.key,
          padding: EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: LongPressDraggable<int>(
            data: index,
            delay: const Duration(milliseconds: 380),
            hapticFeedbackOnStart: true,
            onDragStarted: () => _startDrag(index),
            onDragEnd: (_) => _endDrag(),
            onDraggableCanceled: (_, _) => _endDrag(),
            // Ghost following finger
            feedback: Material(
              color: Colors.transparent,
              child: SizedBox(
                width: screenWidth - 32,
                child: Transform(
                  transform: Matrix4.diagonal3Values(1.04, 1.04, 1.0),
                  alignment: Alignment.topCenter,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.28),
                          blurRadius: 22,
                          spreadRadius: 1,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Opacity(opacity: 0.93, child: entry.child),
                  ),
                ),
              ),
            ),
            // Slot left behind while dragging
            childWhenDragging: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 56,
              decoration: BoxDecoration(
                color: AppTheme.accent.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppTheme.accent.withValues(alpha: 0.28),
                  width: 1.5,
                ),
              ),
            ),
            child: DragTarget<int>(
              onWillAcceptWithDetails: (details) {
                if (details.data == index) return false;
                _updateHover(index);
                return true;
              },
              onLeave: (_) => _clearHover(),
              onAcceptWithDetails: (details) => _drop(details.data, index),
              builder: (context, candidateData, _) {
                final isTarget = candidateData.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOut,
                  transform: Matrix4.diagonal3Values(
                    isDraggingThis ? 0.96 : 1.0,
                    isDraggingThis ? 0.96 : 1.0,
                    1.0,
                  ),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: isTarget
                        ? Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.65),
                            width: 2,
                          )
                        : null,
                    boxShadow: isTarget
                        ? [
                            BoxShadow(
                              color: AppTheme.accent.withValues(alpha: 0.18),
                              blurRadius: 14,
                              spreadRadius: 2,
                            ),
                          ]
                        : null,
                  ),
                  child: entry.child,
                );
              },
            ),
          ),
        );
      }),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LOADING CARD PLACEHOLDER
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(child: CupertinoActivityIndicator(radius: 12)),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  WEEK OVERVIEW CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _WeekOverviewCard extends StatelessWidget {
  final List<TimetableEntry> allWeek;
  final DateTime now;
  final WebUntisService service;

  const _WeekOverviewCard({
    required this.allWeek,
    required this.now,
    required this.service,
  });

  static const _dayLabels = ['Mo', 'Di', 'Mi', 'Do', 'Fr'];
  static const _weekdays = [
    'Montag',
    'Dienstag',
    'Mittwoch',
    'Donnerstag',
    'Freitag',
    'Samstag',
    'Sonntag',
  ];
  static const _months = [
    'Januar',
    'Februar',
    'März',
    'April',
    'Mai',
    'Juni',
    'Juli',
    'August',
    'September',
    'Oktober',
    'November',
    'Dezember',
  ];

  int _dateInt(DateTime d) => int.parse(
    '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}',
  );

  @override
  Widget build(BuildContext context) {
    final monday = now.subtract(Duration(days: now.weekday - 1));

    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.tint.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 12,
                    color: AppTheme.tint,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Diese Woche',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_weekdays[now.weekday - 1]}, ${now.day}. ${_months[now.month - 1]}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: AppTheme.textTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: List.generate(5, (i) {
              final day = monday.add(Duration(days: i));
              final dateInt = _dateInt(day);
              final dayEntries = allWeek
                  .where((e) => e.date == dateInt)
                  .toList();
              final isToday =
                  day.year == now.year &&
                  day.month == now.month &&
                  day.day == now.day;
              final isPast = day.isBefore(
                DateTime(now.year, now.month, now.day),
              );
              final hasExam = dayEntries.any((e) => e.isExam);
              final hasCancelled = dayEntries.any((e) => e.isCancelled);

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? AppTheme.accent
                            : AppTheme.textTertiary,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: isToday
                            ? AppTheme.accent
                            : hasExam
                            ? AppTheme.warning.withValues(alpha: 0.15)
                            : hasCancelled
                            ? AppTheme.danger.withValues(alpha: 0.10)
                            : AppTheme.card,
                        shape: BoxShape.circle,
                        border: hasExam && !isToday
                            ? Border.all(
                                color: AppTheme.warning.withValues(alpha: 0.5),
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Center(
                        child: hasExam
                            ? Icon(
                                CupertinoIcons.doc_text_fill,
                                size: 12,
                                color: isToday
                                    ? Colors.white
                                    : AppTheme.warning,
                              )
                            : Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? Colors.white
                                      : isPast
                                      ? AppTheme.textTertiary
                                      : AppTheme.textPrimary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    if (hasCancelled && !hasExam)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.6),
                          shape: BoxShape.circle,
                        ),
                      )
                    else
                      const SizedBox(height: 4),
                  ],
                ),
              );
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _WeekLegendDot(color: AppTheme.warning, label: 'Prüfung'),
              const SizedBox(width: 12),
              _WeekLegendDot(color: AppTheme.danger, label: 'Entfall'),
              const Spacer(),
              Text(
                '${allWeek.length} Std. diese Woche',
                style: TextStyle(fontSize: 10, color: AppTheme.textTertiary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  EXAM BANNER
// ═══════════════════════════════════════════════════════════════════════════════

class _ExamBanner extends StatelessWidget {
  final _NextExam? nextExam;
  const _ExamBanner({required this.nextExam});

  @override
  Widget build(BuildContext context) {
    if (nextExam == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: AppTheme.success.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppTheme.success.withValues(alpha: 0.22),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            Icon(
              CupertinoIcons.checkmark_seal_fill,
              size: 13,
              color: AppTheme.success,
            ),
            const SizedBox(width: 7),
            const Text(
              'Keine Prüfung diese Woche',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppTheme.success,
              ),
            ),
          ],
        ),
      );
    }

    final exam = nextExam!;
    final color = exam.isToday ? AppTheme.danger : AppTheme.warning;
    final icon = exam.isToday
        ? CupertinoIcons.exclamationmark_circle_fill
        : CupertinoIcons.calendar_badge_plus;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  exam.isToday ? 'Prüfung heute' : 'Nächste Prüfung',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: color.withValues(alpha: 0.85),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  exam.entry.displayName,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  exam.label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: color.withValues(alpha: 0.65),
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

// ═══════════════════════════════════════════════════════════════════════════════
//  TIME INFO CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _TimeInfoCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String sub;
  final Color color;

  const _TimeInfoCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Center(child: Icon(icon, size: 11, color: color)),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: AppTheme.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            sub,
            style: TextStyle(fontSize: 10, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  MENSA PREVIEW CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _MensaPreviewCard extends StatelessWidget {
  final String? dish;
  final String? category;
  final bool loading;
  const _MensaPreviewCard({this.dish, this.category, required this.loading});

  static const _kOrange = Color(0xFFFF6B35);
  static const _kAmber = Color(0xFFFF9500);

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(13),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _kOrange.withValues(alpha: 0.18),
            _kAmber.withValues(alpha: 0.07),
          ],
        ),
        border: Border.all(color: _kOrange.withValues(alpha: 0.25), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.flame_fill,
                      size: 12,
                      color: _kOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  'Mensa',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 6),
                child: CupertinoActivityIndicator(radius: 8),
              )
            else if (dish != null) ...[
              const SizedBox(height: 5),
              Text(
                dish!,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.textPrimary,
                  height: 1.3,
                ),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Text(
                    'Zum Menü',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: _kOrange,
                    ),
                  ),
                  const SizedBox(width: 3),
                  Icon(
                    CupertinoIcons.arrow_right,
                    size: 9,
                    color: _kOrange.withValues(alpha: 0.8),
                  ),
                ],
              ),
            ] else
              Text(
                'Heute nichts\nverfügbar',
                style: TextStyle(
                  fontSize: 12,
                  color: AppTheme.textSecondary,
                  height: 1.4,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  RECENT GRADES CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _RecentGradesCard extends StatelessWidget {
  final List<_RecentGrade> grades;
  final double? average;
  final bool loading;
  const _RecentGradesCard({
    required this.grades,
    required this.loading,
    this.average,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: AppTheme.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.chart_bar_fill,
                    size: 12,
                    color: AppTheme.accent,
                  ),
                ),
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  'Letzte Noten',
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
          if (loading)
            const CupertinoActivityIndicator(radius: 8)
          else if (grades.isEmpty)
            Text(
              'Noch keine Noten',
              style: TextStyle(fontSize: 11, color: AppTheme.textSecondary),
            )
          else
            Column(children: grades.map((g) => _GradeRow(grade: g)).toList()),
        ],
      ),
    );
  }
}

class _GradeRow extends StatelessWidget {
  final _RecentGrade grade;
  const _GradeRow({required this.grade});

  Color _gradeColor(double v) {
    if (v >= 9) return AppTheme.success;
    if (v >= 6.5) return const Color(0xFF86EFAC);
    if (v >= 6) return AppTheme.warning;
    if (v >= 4) return const Color(0xFFFF9F0A);
    return AppTheme.danger;
  }

  String _fmtValue(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '');
  }

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade.value);
    final d = grade.date.toString();
    final dateStr = d.length == 8
        ? '${d.substring(6)}.${d.substring(4, 6)}'
        : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              grade.subject,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: AppTheme.textPrimary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            dateStr,
            style: TextStyle(fontSize: 9, color: AppTheme.textTertiary),
          ),
          const SizedBox(width: 4),
          Container(
            constraints: const BoxConstraints(minWidth: 28),
            height: 20,
            padding: const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(5),
            ),
            child: Center(
              child: Text(
                _fmtValue(grade.value),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekLegendDot extends StatelessWidget {
  final Color color;
  final String label;
  const _WeekLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
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

// ═══════════════════════════════════════════════════════════════════════════════
//  ERROR CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _ErrorCard extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorCard({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          const Icon(
            CupertinoIcons.exclamationmark_triangle_fill,
            color: AppTheme.danger,
            size: 24,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 12),
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
            color: AppTheme.accent,
            borderRadius: BorderRadius.circular(9),
            minimumSize: Size.zero,
            onPressed: onRetry,
            child: const Text(
              'Erneut versuchen',
              style: TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}
