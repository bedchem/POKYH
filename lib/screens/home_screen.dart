import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/update_service.dart';
import '../services/notification_service.dart';
import '../services/auth_service.dart';
import '../services/webuntis_service.dart';
import '../services/dish_service.dart';
import '../theme/app_theme.dart';
import '../utils/error_message.dart';
import 'timetable_screen.dart' show TimetableScreen, TimetableScreenState;
import 'mensa_screen.dart';
import 'login_screen.dart';
import 'profile_screen.dart';
import 'messages_screen.dart';
import 'hub_screen.dart';

class _DS {
  static const accent = Color(0xFF6366F1);
  static const accentGreen = Color(0xFF10B981);
  static const accentYellow = Color(0xFFF59E0B);
  static const accentOrange = Color(0xFFF97316);
  static const accentRed = Color(0xFFEF4444);
  static const textTertiary = Color(0xFF52525F);
  static const radius = 14.0;
}

class HomeScreen extends StatefulWidget {
  final WebUntisService service;
  final bool fromRestore;
  const HomeScreen({super.key, required this.service, this.fromRestore = false});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  int _tab = 0;
  late final List<Widget> _screens;
  late final PageController _swipePageController;
  late GlobalKey<TimetableScreenState> _timetableKey;
  late final MensaScreenController _mensaController;
  int _unreadMessages = 0;

  static const List<int> _swipeTabs = [0, 1, 2, 3];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _swipePageController = PageController(initialPage: 0);
    _timetableKey = TimetableScreen.createKey();
    _mensaController = MensaScreenController();
    NotificationService().onNewMessages = _showNewMessageBanner;
    NotificationService().startPolling(widget.service);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 900), _checkForUpdate);
      _fetchUnreadCount();
      if (widget.fromRestore) _initRestoreSession();
    });
    _screens = [
      _DashboardTab(
        service: widget.service,
        onMensaTap: _showMensaTab,
        onSessionExpired: _handleSessionExpired,
        onExamTap: (exam) {
          if (exam == null) return;
          _setTab(1);
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
      HubScreen(service: widget.service),
      MensaScreen(controller: _mensaController, service: widget.service),
    ];
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService().stopPolling();
    NotificationService().onNewMessages = null;
    _swipePageController.dispose();
    super.dispose();
  }

  DateTime? _backgroundedAt;
  static const _inactivityTimeout = Duration(minutes: 1);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      widget.service.saveSession().ignore();
      NotificationService().stopPolling();
    } else if (state == AppLifecycleState.resumed) {
      final backgroundedAt = _backgroundedAt;
      _backgroundedAt = null;
      if (backgroundedAt != null &&
          DateTime.now().difference(backgroundedAt) >= _inactivityTimeout) {
        widget.service.clearSession();
        if (!mounted) return;
        Navigator.of(context).pushAndRemoveUntil(
          PageRouteBuilder(
            pageBuilder: (_, _, _) => const LoginScreen(),
            transitionsBuilder: (_, a, _, child) =>
                FadeTransition(opacity: a, child: child),
            transitionDuration: const Duration(milliseconds: 300),
          ),
          (route) => false,
        );
      } else {
        NotificationService().startPolling(widget.service);
      }
    }
  }

  void _showMensaTab() {
    _mensaController.scrollToTop();
    _setTab(3);
  }

  int? _swipeIndexForTab(int tab) {
    final index = _swipeTabs.indexOf(tab);
    return index >= 0 ? index : null;
  }

  int _tabForSwipeIndex(int index) =>
      _swipeTabs[index.clamp(0, _swipeTabs.length - 1)];

  void _setTab(int tab, {bool animate = true}) {
    if (_tab == tab) return;
    final targetSwipeIndex = _swipeIndexForTab(tab);
    if (targetSwipeIndex == null) return;
    setState(() => _tab = tab);

    void syncSwipePage() {
      if (!_swipePageController.hasClients) return;
      final current =
          _swipePageController.page?.round() ??
          _swipePageController.initialPage;
      if (current == targetSwipeIndex) return;
      if (animate) {
        _swipePageController.animateToPage(
          targetSwipeIndex,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeInOutCubic,
        );
      } else {
        _swipePageController.jumpToPage(targetSwipeIndex);
      }
    }

    if (_swipePageController.hasClients) {
      syncSwipePage();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        syncSwipePage();
      });
    }
  }

  Widget _buildMainContent() {
    return PageView(
      controller: _swipePageController,
      physics: _tab == 1
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      onPageChanged: (index) {
        final nextTab = _tabForSwipeIndex(index);
        if (nextTab != _tab) setState(() => _tab = nextTab);
      },
      children: _screens,
    );
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

  // Called once after session restore — kicks off backend auth and data prefetch
  // in the background so the first render is instant.
  void _initRestoreSession() {
    final service = widget.service;
    final username = service.username;
    if (username == null) return;
    AuthService.instance
        .signIn(username, klasseId: service.klasseId, klasseName: service.klasseName)
        .catchError((e) => debugPrint('[HomeScreen] Backend auth failed: $e'));
    service.fetchProfileImage().ignore();
    service.getAllGrades().ignore();
    service.getAbsences().ignore();
  }

  Future<void> _handleSessionExpired() async {
    NotificationService().stopPolling();
    widget.service.clearSession();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (_, _, _) => const LoginScreen(),
        transitionsBuilder: (_, a, _, child) =>
            FadeTransition(opacity: a, child: child),
        transitionDuration: const Duration(milliseconds: 300),
      ),
      (route) => false,
    );
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
            const Icon(CupertinoIcons.bell_fill, color: Colors.white, size: 18),
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
    if (mounted) {
      setState(() => _unreadMessages = widget.service.unreadMessageCount);
    }
  }

  void _openProfile() {
    Navigator.push(
      context,
      CupertinoPageRoute(
        builder: (_) => ProfileScreen(
          service: widget.service,
          onLogout: _logout,
          onCacheCleared: () {
            if (mounted) _fetchUnreadCount();
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.appBg,
      body: Stack(
        children: [
          _buildMainContent(),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
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
      bottomNavigationBar: _PokyhBottomNav(
        currentTab: _tab,
        onTabChanged: (tab) {
          if (tab == 1 && _tab == 1) {
            final now = DateTime.now();
            final isWeekend = now.weekday >= 6;
            _timetableKey.currentState?.jumpToWeekAndDay(
              weekOffset: isWeekend ? 1 : 0,
              dayIndex: isWeekend ? 0 : now.weekday - 1,
            );
          }
          if (tab == 3) {
            _showMensaTab();
          } else {
            _setTab(tab);
          }
        },
        pageController: _swipePageController,
        swipeTabs: _swipeTabs,
        layout: _HomeNavLayout.forPlatform(Theme.of(context).platform),
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
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: context.appSurface,
        border: Border.all(color: context.appBorder, width: 1.5),
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

  Widget _fallback() => const Center(
    child: Icon(CupertinoIcons.person_fill, size: 16, color: _DS.accent),
  );
}

// ── Message Badge Icon ───────────────────────────────────────────────────────

class _MessageBadgeIcon extends StatelessWidget {
  final int unreadCount;
  const _MessageBadgeIcon({required this.unreadCount});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 36,
      height: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: context.appSurface,
              border: Border.all(color: context.appBorder, width: 1.5),
            ),
            child: const Center(
              child: Icon(
                CupertinoIcons.chat_bubble_fill,
                size: 16,
                color: _DS.accent,
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
                  border: Border.all(color: context.appBg, width: 1.5),
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

class _HomeNavLayout {
  final double barHeight;
  final double bottomPadding;
  final double contentYOffset;
  final double iconSize;
  final double iconLabelSpacing;
  final double labelFontSize;

  const _HomeNavLayout({
    required this.barHeight,
    required this.bottomPadding,
    required this.contentYOffset,
    required this.iconSize,
    required this.iconLabelSpacing,
    required this.labelFontSize,
  });

  // Android: labels always visible.
  static const android = _HomeNavLayout(
    barHeight: 45,
    bottomPadding: 8,
    contentYOffset: 14,
    iconSize: 20,
    iconLabelSpacing: 2,
    labelFontSize: 10,
  );

  // iOS: frosted glass with labels always visible.
  static const ios = _HomeNavLayout(
    barHeight: 45,
    bottomPadding: 8,
    contentYOffset: 14,
    iconSize: 18,
    iconLabelSpacing: 2,
    labelFontSize: 10,
  );

  static _HomeNavLayout forPlatform(TargetPlatform platform) {
    if (platform == TargetPlatform.iOS) return ios;
    return android;
  }
}

class _PokyhBottomNav extends StatelessWidget {
  final int currentTab;
  final void Function(int) onTabChanged;
  final PageController pageController;
  final List<int> swipeTabs;
  final _HomeNavLayout layout;

  const _PokyhBottomNav({
    required this.currentTab,
    required this.onTabChanged,
    required this.pageController,
    required this.swipeTabs,
    required this.layout,
  });

  static const _items = [
    (CupertinoIcons.house_fill, 'Home'),
    (CupertinoIcons.calendar, 'Stundenplan'),
    (CupertinoIcons.square_grid_2x2_fill, 'Schule'),
    (CupertinoIcons.flame_fill, 'Mensa'),
  ];

  void _handleDragUpdate(BuildContext context, DragUpdateDetails details) {
    if (!pageController.hasClients) return;
    final screenWidth = MediaQuery.of(context).size.width;
    final delta = details.primaryDelta ?? 0;
    final current = pageController.page ?? currentTab.toDouble();
    final newPage = (current - delta / screenWidth).clamp(
      0.0,
      (swipeTabs.length - 1).toDouble(),
    );
    pageController.jumpTo(newPage * screenWidth);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (!pageController.hasClients) return;
    final velocity = details.primaryVelocity ?? 0;
    final currentPage = pageController.page ?? currentTab.toDouble();
    int targetPage;
    if (velocity < -400) {
      targetPage = (currentPage.floor() + 1).clamp(0, swipeTabs.length - 1);
    } else if (velocity > 400) {
      targetPage = (currentPage.ceil() - 1).clamp(0, swipeTabs.length - 1);
    } else {
      targetPage = currentPage.round().clamp(0, swipeTabs.length - 1);
    }
    pageController.animateToPage(
      targetPage,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final isIOS = Theme.of(context).platform == TargetPlatform.iOS;

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragUpdate: (d) => _handleDragUpdate(context, d),
      onHorizontalDragEnd: _handleDragEnd,
      child: isIOS
          ? _buildIOSBar(context, bottomInset)
          : _buildAndroidBar(context, bottomInset),
    );
  }

  // iOS: frosted glass background, labels always visible.
  Widget _buildIOSBar(BuildContext context, double bottomInset) {
    final effectiveBottom = bottomInset / 3 + layout.bottomPadding;
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: EdgeInsets.only(
            bottom: effectiveBottom,
            top: layout.contentYOffset,
          ),
          constraints: BoxConstraints(
            minHeight: layout.barHeight + effectiveBottom,
          ),
          decoration: BoxDecoration(
            color: context.appSurface.withValues(alpha: 0.72),
            border: Border(
              top: BorderSide(
                color: context.appBorder.withValues(alpha: 0.5),
                width: 0.5,
              ),
            ),
          ),
          child: Row(
            children: List.generate(_items.length, (i) {
              final (icon, label) = _items[i];
              final active = currentTab == i;
              return Expanded(
                child: _NavItem(
                  icon: icon,
                  label: label,
                  active: active,
                  onTap: () => onTabChanged(i),
                  layout: layout,
                  showLabel: true,
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  // Android: solid surface, icon-only (no labels), Material 3 feel.
  Widget _buildAndroidBar(BuildContext context, double bottomInset) {
    return Container(
      padding: EdgeInsets.only(
        bottom: bottomInset + layout.bottomPadding,
        top: layout.contentYOffset,
      ),
      constraints: BoxConstraints(
        minHeight: layout.barHeight + bottomInset + layout.bottomPadding,
      ),
      decoration: BoxDecoration(
        color: context.appSurface,
        border: Border(top: BorderSide(color: context.appBorder, width: 0.5)),
      ),
      child: Row(
        children: List.generate(_items.length, (i) {
          final (icon, label) = _items[i];
          final active = currentTab == i;
          return Expanded(
            child: _NavItem(
              icon: icon,
              label: label,
              active: active,
              onTap: () => onTabChanged(i),
              layout: layout,
              showLabel: true,
            ),
          );
        }),
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  final _HomeNavLayout layout;
  final bool showLabel;

  const _NavItem({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
    required this.layout,
    this.showLabel = true,
  });

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: widget.showLabel ? 8 : 10,
                vertical: 6,
              ),
              decoration: BoxDecoration(
                color: widget.active
                    ? _DS.accent.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(
                widget.icon,
                size: widget.layout.iconSize,
                color: widget.active ? _DS.accent : context.appTextTertiary,
              ),
            ),
            if (widget.showLabel) ...[
              SizedBox(height: widget.layout.iconLabelSpacing),
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: widget.layout.labelFontSize,
                  fontWeight: widget.active ? FontWeight.w600 : FontWeight.w400,
                  color: widget.active ? _DS.accent : context.appTextTertiary,
                ),
              ),
            ],
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
  final String markName;
  final int date;
  final int lastUpdate;
  final String type;
  const _RecentGrade({
    required this.subject,
    required this.value,
    required this.markName,
    required this.date,
    required this.lastUpdate,
    required this.type,
  });
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CARD SECTION ENUM + PERSISTENCE
// ═══════════════════════════════════════════════════════════════════════════════

// Neue Reihenfolge:
// 1. weekOverview   – Wochenübersicht (oben, immer)
// 2. todaySection   – "Heute": Mensa + Schulende/Stunden in einer Karte
// 3. nextExam       – Nächste Schularbeit
// 4. recentGrades   – Letzte Noten
enum _CardSection { weekOverview, todaySection, nextExam, recentGrades }

const _kCardOrderKey = 'dashboard_card_order_v2';

final _defaultOrder = [
  _CardSection.weekOverview,
  _CardSection.todaySection,
  _CardSection.nextExam,
  _CardSection.recentGrades,
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
  final VoidCallback? onSessionExpired;
  const _DashboardTab({
    required this.service,
    required this.onMensaTap,
    this.onExamTap,
    this.onSessionExpired,
  });

  @override
  State<_DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<_DashboardTab>
    with SingleTickerProviderStateMixin {
  // ── Timetable state ──────────────────────────────────────────────────────
  List<TimetableEntry> _today = [];
  List<TimetableEntry> _allWeek = [];
  List<TimetableEntry> _allFutureExams = [];
  bool _isWeekend = false;
  bool _loadingTimetable = true;
  String? _errorTimetable;

  // ── Grades state ─────────────────────────────────────────────────────────
  List<_RecentGrade> _recentGrades = [];
  double? _weekAverage;
  bool _loadingGrades = true;

  // ── Mensa state ──────────────────────────────────────────────────────────
  String? _mensaToday;
  String? _mensaCategory;
  bool _loadingMensa = true;

  // ── Card order ────────────────────────────────────────────────────────────
  List<_CardSection> _cardOrder = List.from(_defaultOrder);

  late AnimationController _fadeController;

  @override
  void initState() {
    super.initState();
    _isWeekend = DateTime.now().weekday >= 6;
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
    _isWeekend = DateTime.now().weekday >= 6;
    _applyGradesCache(widget.service.cachedGrades);
    final cachedWeek = widget.service.getCachedWeek(_getDisplayMonday());
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

  DateTime _getDisplayMonday() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final thisMonday = today.subtract(Duration(days: today.weekday - 1));
    if (now.weekday >= 6) return thisMonday.add(const Duration(days: 7));
    return thisMonday;
  }

  void _applyTimetableCache(List<TimetableEntry> allWeek) {
    final now = DateTime.now();
    final todayInt = _dateInt(now);
    _allWeek = allWeek;
    _today = now.weekday < 6
        ? allWeek.where((e) => e.date == todayInt).toList()
        : [];
    _allFutureExams = allWeek.where((e) => e.isExam).toList();
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
            markName: grade.markName,
            date: grade.date,
            lastUpdate: grade.lastUpdate,
            type: grade.examType,
          ),
        );
        sum += grade.markDisplayValue;
        count++;
      }
    }
    allGrades.sort((a, b) => b.lastUpdate.compareTo(a.lastUpdate));
    _recentGrades = allGrades.take(5).toList();
    _weekAverage = count > 0 ? sum / count : null;
    _loadingGrades = false;
  }

  Future<void> _loadTimetable() async {
    try {
      final now = DateTime.now();
      final displayMonday = _getDisplayMonday();

      final allWeek = await widget.service.getWeekTimetable(
        weekStart: displayMonday,
      );

      // Fetch up to 7 more weeks in parallel to find future exams.
      final futures = <Future<List<TimetableEntry>>>[];
      for (int i = 1; i <= 7; i++) {
        final weekStart = displayMonday.add(Duration(days: 7 * i));
        futures.add(
          widget.service
              .getWeekTimetable(weekStart: weekStart)
              .catchError((_) => <TimetableEntry>[]),
        );
      }
      final futureWeeks = await Future.wait(futures);
      final futureExams = <TimetableEntry>[
        ...allWeek.where((e) => e.isExam),
        for (final week in futureWeeks) ...week.where((e) => e.isExam),
      ];

      final todayInt = _dateInt(now);
      if (mounted) {
        setState(() {
          _allWeek = allWeek;
          _today = now.weekday < 6
              ? allWeek.where((e) => e.date == todayInt).toList()
              : [];
          _allFutureExams = futureExams;
          _loadingTimetable = false;
        });
      }
    } on WebUntisException catch (e) {
      if (e.isAuthError) {
        widget.onSessionExpired?.call();
        return;
      }
      if (mounted) {
        setState(() {
          _errorTimetable = e.message;
          _loadingTimetable = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorTimetable = simplifyErrorMessage(e);
          _loadingTimetable = false;
        });
      }
    }
  }

  Future<void> _loadGrades() async {
    try {
      final subjects = await widget.service.getAllGrades();
      if (mounted) setState(() => _applyGradesCache(subjects));
    } catch (e) {
      if (e is WebUntisException && e.isAuthError) {
        widget.onSessionExpired?.call();
        return;
      }
      if (mounted) setState(() => _loadingGrades = false);
    }
  }

  Future<void> _loadMensa() async {
    try {
      final dishService = DishService();
      final dishes =
          await dishService.fetchFromServer(untisService: widget.service) ??
          await dishService.loadFromCache(untisService: widget.service);
      if (!mounted) return;
      if (dishes == null || dishes.isEmpty) {
        setState(() {
          _mensaToday = null;
          _loadingMensa = false;
        });
        return;
      }
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      // On weekends, show no menu for today
      final targetDate = today;

      final targetDishes = dishes.where((d) {
        final key = DateTime(d.date.year, d.date.month, d.date.day);
        return key == targetDate;
      }).toList();

      if (targetDishes.isEmpty) {
        setState(() {
          _mensaToday = null;
          _loadingMensa = false;
        });
        return;
      }
      final main = targetDishes.firstWhere(
        (d) => d.category.toLowerCase().contains('haupt'),
        orElse: () => targetDishes.first,
      );
      setState(() {
        _mensaToday = main.name('de');
        _mensaCategory = main.category.isNotEmpty ? main.category : null;
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
        _allFutureExams.where((e) {
          if (!e.isExam) return false;
          if (e.date > todayInt) return true;
          if (e.date < todayInt) return false;
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
    } else if (diff < 7) {
      const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      label = 'in $diff Tagen (${wd[examDate.weekday - 1]})';
    } else {
      const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
      const mo = [
        'Jan',
        'Feb',
        'März',
        'Apr',
        'Mai',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Okt',
        'Nov',
        'Dez',
      ];
      label =
          '${wd[examDate.weekday - 1]}, ${examDate.day}. ${mo[examDate.month - 1]}';
    }

    return _NextExam(
      entry: e,
      label: label,
      isToday: diff == 0,
      daysUntil: diff,
    );
  }

  String _greetingName() {
    final name = widget.service.username ?? '';
    final parts = name.trim().split(' ');
    return parts.isNotEmpty && parts.first.isNotEmpty ? parts.first : 'Schüler';
  }

  String _greeting() {
    final h = DateTime.now().hour;
    if (h < 11) return 'Guten Morgen';
    if (h < 17) return 'Guten Tag';
    return 'Guten Abend';
  }

  String _dayString() {
    final now = DateTime.now();
    const days = [
      'Montag',
      'Dienstag',
      'Mittwoch',
      'Donnerstag',
      'Freitag',
      'Samstag',
      'Sonntag',
    ];
    const months = [
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
    return '${days[now.weekday - 1]}, ${now.day}. ${months[now.month - 1]} ${now.year}';
  }

  // ── Card content builders ──────────────────────────────────────────────────

  Widget? _cardContent(_CardSection section, DateTime now) {
    final nextExam = _getNextExam(now);
    final schoolEnd = _getSchoolEnd();
    final minsUntilEnd = _minsUntilEnd(now);

    switch (section) {
      // ── 1. Week overview (always shown, loading spinner if needed) ──────
      case _CardSection.weekOverview:
        if (_loadingTimetable && _allWeek.isEmpty) {
          return const _LoadingCard();
        }
        return _WeekOverviewCard(
          allWeek: _allWeek,
          now: now,
          displayMonday: _getDisplayMonday(),
          service: widget.service,
        );

      // ── 2. Today section: Mensa top, then school-end + lessons row ──────
      case _CardSection.todaySection:
        return _TodaySectionCard(
          isWeekend: _isWeekend,
          mensaToday: _mensaToday,
          mensaCategory: _mensaCategory,
          loadingMensa: _loadingMensa,
          schoolEnd: schoolEnd,
          minsUntilEnd: minsUntilEnd,
          todayLessons: _today.length,
          loadingTimetable: _loadingTimetable,
          errorTimetable: _errorTimetable,
          gradeAverage: _weekAverage,
          onMensaTap: widget.onMensaTap,
          onRetry: _load,
        );

      // ── 3. Next exam (always shown; spinner while loading) ───────────────
      case _CardSection.nextExam:
        if (_errorTimetable != null && _allFutureExams.isEmpty) return null;
        return GestureDetector(
          onTap: nextExam != null
              ? () => widget.onExamTap?.call(nextExam)
              : null,
          child: _loadingTimetable && _allFutureExams.isEmpty
              ? Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: context.appSurface,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _SectionHeader(label: 'NÄCHSTE SCHULARBEIT'),
                      const SizedBox(height: 12),
                      const _LoadingCard(),
                    ],
                  ),
                )
              : _ExamCard(nextExam: nextExam),
        );

      // ── 4. Recent grades (always shown) ──────────────────────────────────
      case _CardSection.recentGrades:
        return _RecentGradesCard(
          grades: _recentGrades,
          average: _weekAverage,
          loading: _loadingGrades,
        );
    }
  }

  void _onReorder(int oldIndex, int newIndex) {
    HapticFeedback.lightImpact();
    setState(() {
      final now = DateTime.now();
      final visible = _cardOrder
          .where((s) => _cardContent(s, now) != null)
          .toList();
      final movedSection = visible[oldIndex];
      _cardOrder.remove(movedSection);
      final newVisible = _cardOrder
          .where((s) => _cardContent(s, now) != null)
          .toList();
      if (newIndex >= newVisible.length) {
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
    final visibleCards = _cardOrder
        .map((s) => (section: s, content: _cardContent(s, now)))
        .where((pair) => pair.content != null)
        .toList();

    return Container(
      color: context.appBg,
      child: SafeArea(
        child: RefreshIndicator(
          color: _DS.accent,
          backgroundColor: context.appSurface,
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 70, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _dayString(),
                        style: TextStyle(
                          fontSize: 13,
                          color: context.appTextSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      RichText(
                        text: TextSpan(
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: context.appTextPrimary,
                            height: 1.15,
                          ),
                          children: [
                            TextSpan(text: '${_greeting()},\n'),
                            TextSpan(
                              text: _greetingName(),
                              style: const TextStyle(color: _DS.accent),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 24)),
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
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  SECTION HEADER HELPER
// ═══════════════════════════════════════════════════════════════════════════════

class _SectionHeader extends StatelessWidget {
  final String label;
  final String? sublabel;

  const _SectionHeader({required this.label, this.sublabel});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.9,
            color: context.appTextTertiary,
          ),
        ),
        if (sublabel != null) ...[
          Text(
            ' · ',
            style: TextStyle(color: context.appTextTertiary, fontSize: 11),
          ),
          Text(
            sublabel!,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.9,
              color: context.appTextTertiary,
            ),
          ),
        ],
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  TODAY SECTION CARD
//  Layout: HEUTE header → Mensa preview → Schulende + Stunden (row)
// ═══════════════════════════════════════════════════════════════════════════════

class _TodaySectionCard extends StatelessWidget {
  final bool isWeekend;
  final String? mensaToday;
  final String? mensaCategory;
  final bool loadingMensa;
  final String? schoolEnd;
  final int? minsUntilEnd;
  final int todayLessons;
  final bool loadingTimetable;
  final String? errorTimetable;
  final double? gradeAverage;
  final VoidCallback onMensaTap;
  final VoidCallback onRetry;

  static const _kOrange = Color(0xFFF97316);

  const _TodaySectionCard({
    required this.isWeekend,
    required this.mensaToday,
    required this.mensaCategory,
    required this.loadingMensa,
    required this.schoolEnd,
    required this.minsUntilEnd,
    required this.todayLessons,
    required this.loadingTimetable,
    required this.errorTimetable,
    this.gradeAverage,
    required this.onMensaTap,
    required this.onRetry,
  });

  String _fmtDuration(int mins) {
    if (mins < 60) return '${mins}min';
    final h = mins ~/ 60;
    final m = mins % 60;
    return m == 0 ? '${h}h' : '${h}h ${m}min';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final surface = context.appSurface;
    const months = [
      'Jan',
      'Feb',
      'März',
      'Apr',
      'Mai',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Okt',
      'Nov',
      'Dez',
    ];
    final dayLabel = '${now.day}. ${months[now.month - 1]}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(label: 'HEUTE', sublabel: dayLabel),
        const SizedBox(height: 10),

        GestureDetector(
          onTap: onMensaTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(_DS.radius),
              border: Border.all(
                color: _kOrange.withValues(alpha: 0.18),
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _kOrange.withValues(alpha: 0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Center(
                    child: Icon(
                      CupertinoIcons.flame_fill,
                      size: 18,
                      color: _kOrange,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: loadingMensa
                      ? const CupertinoActivityIndicator(radius: 8)
                      : mensaToday != null
                      ? Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mensa heute',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: _kOrange,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              mensaToday!,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: context.appTextPrimary,
                                height: 1.35,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        )
                      : Text(
                          'Heute gibt es nichts',
                          style: TextStyle(
                            fontSize: 13,
                            color: context.appTextSecondary,
                          ),
                        ),
                ),
                const SizedBox(width: 10),
                Icon(
                  CupertinoIcons.chevron_right,
                  size: 14,
                  color: context.appTextTertiary,
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 10),

        if (errorTimetable != null && !loadingTimetable)
          _ErrorCard(message: errorTimetable!, onRetry: onRetry)
        else
          Row(
            children: [
              _StatMiniCard(
                icon: CupertinoIcons.flag_fill,
                iconColor: _DS.accent,
                label: 'Schulende',
                loading: loadingTimetable,
                value: isWeekend ? '—' : schoolEnd ?? '—',
                sub: isWeekend
                    ? 'Wochenende'
                    : minsUntilEnd != null
                    ? 'noch ${_fmtDuration(minsUntilEnd!)}'
                    : schoolEnd == null
                    ? 'kein Unterricht'
                    : 'vorbei',
                valueColor: minsUntilEnd != null ? _DS.accent : null,
              ),
              const SizedBox(width: 8),
              _StatMiniCard(
                icon: CupertinoIcons.chart_bar_fill,
                iconColor: _avgColor(gradeAverage),
                label: 'Schnitt',
                loading: false,
                value: gradeAverage != null
                    ? gradeAverage!.toStringAsFixed(1)
                    : '—',
                sub: gradeAverage != null ? 'Notenschnitt' : 'Kein Schnitt',
                valueColor: _avgColor(gradeAverage),
              ),
              const SizedBox(width: 8),
              _StatMiniCard(
                icon: CupertinoIcons.book_fill,
                iconColor: _DS.accentYellow,
                label: 'Stunden',
                loading: loadingTimetable,
                value: isWeekend ? '—' : '$todayLessons',
                sub: isWeekend
                    ? 'Wochenende'
                    : todayLessons == 0
                    ? 'kein Unterricht'
                    : 'heute',
                valueColor: null,
              ),
            ],
          ),
      ],
    );
  }

  static Color _avgColor(double? avg) {
    if (avg == null) return _DS.textTertiary;
    if (avg >= 6.5) return _DS.accentGreen;
    if (avg >= 6.0) return _DS.accentOrange;
    return _DS.accentRed;
  }
}

class _StatMiniCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final bool loading;
  final String value;
  final String sub;
  final Color? valueColor;
  const _StatMiniCard({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.loading,
    required this.value,
    required this.sub,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
        decoration: BoxDecoration(
          color: context.appSurface,
          borderRadius: BorderRadius.circular(_DS.radius),
          border: Border.all(color: context.appBorder.withValues(alpha: 0.6)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Center(child: Icon(icon, size: 10, color: iconColor)),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: context.appTextSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (loading)
              const CupertinoActivityIndicator(radius: 7)
            else ...[
              Text(
                value,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: valueColor ?? context.appTextPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 3),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 9,
                  color: context.appTextSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  EXAM CARD  (nächste Schularbeit)
// ═══════════════════════════════════════════════════════════════════════════════

class _ExamCard extends StatelessWidget {
  final _NextExam? nextExam;
  const _ExamCard({required this.nextExam});

  Color _chipColor(_NextExam exam) {
    if (exam.isToday) return _DS.accentRed;
    if (exam.daysUntil <= 3) return _DS.accentOrange;
    if (exam.daysUntil <= 7) return _DS.accentYellow;
    return _DS.accent;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(label: 'NÄCHSTE SCHULARBEIT'),
        const SizedBox(height: 10),
        if (nextExam == null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: _DS.accentGreen.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(_DS.radius),
              border: Border.all(
                color: _DS.accentGreen.withValues(alpha: 0.22),
                width: 1,
              ),
            ),
            child: Row(
              children: const [
                Icon(
                  CupertinoIcons.checkmark_seal_fill,
                  size: 16,
                  color: _DS.accentGreen,
                ),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Keine Schularbeit gefunden',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: _DS.accentGreen,
                    ),
                  ),
                ),
              ],
            ),
          )
        else
          Builder(
            builder: (context) {
              final exam = nextExam!;
              final color = _chipColor(exam);
              final d = exam.entry.date.toString();
              final examDate = DateTime(
                int.parse(d.substring(0, 4)),
                int.parse(d.substring(4, 6)),
                int.parse(d.substring(6, 8)),
              );
              const wd = ['Mo', 'Di', 'Mi', 'Do', 'Fr', 'Sa', 'So'];
              const mo = [
                'Jan',
                'Feb',
                'März',
                'Apr',
                'Mai',
                'Jun',
                'Jul',
                'Aug',
                'Sep',
                'Okt',
                'Nov',
                'Dez',
              ];
              final dateStr =
                  '${wd[examDate.weekday - 1]}., ${examDate.day}. ${mo[examDate.month - 1]}';
              final timeStr =
                  '${(exam.entry.startTime ~/ 100).toString().padLeft(2, '0')}:${(exam.entry.startTime % 100).toString().padLeft(2, '0')}';

              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: context.appSurface,
                  borderRadius: BorderRadius.circular(_DS.radius),
                  border: Border.all(
                    color: color.withValues(alpha: 0.25),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Icon(
                          CupertinoIcons.doc_text_fill,
                          size: 18,
                          color: color,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exam.entry.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: context.appTextPrimary,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            '$dateStr · $timeStr · ${exam.entry.roomName}',
                            style: TextStyle(
                              fontSize: 11,
                              color: context.appTextSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        exam.label,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: color,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
      ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionHeader(label: 'LETZTE NOTEN'),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            color: context.appSurface,
            borderRadius: BorderRadius.circular(_DS.radius),
            border: Border.all(
              color: const Color.fromARGB(
                255,
                119,
                119,
                119,
              ).withValues(alpha: 0.18),
              width: 0.8,
            ),
          ),
          child: loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 20),
                  child: Center(child: CupertinoActivityIndicator(radius: 10)),
                )
              : grades.isEmpty
              ? Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    'Noch keine Noten',
                    style: TextStyle(
                      color: context.appTextSecondary,
                      fontSize: 13,
                    ),
                  ),
                )
              : Column(
                  children: grades.indexed.map((pair) {
                    final (i, grade) = pair;
                    final isLast = i == grades.length - 1;
                    return _GradeRow(grade: grade, isLast: isLast);
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _GradeRow extends StatelessWidget {
  final _RecentGrade grade;
  final bool isLast;
  const _GradeRow({required this.grade, required this.isLast});

  Color _gradeColor(double v) {
    if (v >= 9) return _DS.accentGreen;
    if (v >= 6.5) return _DS.accentGreen;
    if (v >= 6) return _DS.accentOrange;
    if (v >= 4) return _DS.accentYellow;
    return _DS.accentRed;
  }

  String _fmtValue(double v) {
    if (v % 1 == 0) return v.toInt().toString();
    var formatted = v.toStringAsFixed(2);
    formatted = formatted.replaceFirst(RegExp(r'0+$'), '');
    formatted = formatted.replaceFirst(RegExp(r'\\.$'), '');
    return formatted;
  }

  String _dateStr(int date) {
    final d = date.toString();
    if (d.length == 8) {
      return '${d.substring(6)}.${d.substring(4, 6)}.';
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    final color = _gradeColor(grade.value);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        border: !isLast
            ? Border(
                bottom: BorderSide(
                  color: const Color.fromARGB(
                    255,
                    119,
                    119,
                    119,
                  ).withValues(alpha: 0.18),
                  width: 0.5,
                ),
              )
            : null,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  grade.subject,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: context.appTextPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${grade.type} · ${_dateStr(grade.date)}',
                  style: TextStyle(
                    fontSize: 11,
                    color: context.appTextSecondary,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                grade.markName.isNotEmpty
                    ? grade.markName
                    : _fmtValue(grade.value),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
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

// ═══════════════════════════════════════════════════════════════════════════════
//  WEEK OVERVIEW CARD  (unverändert aus deinem Code)
// ═══════════════════════════════════════════════════════════════════════════════

class _WeekOverviewCard extends StatelessWidget {
  final List<TimetableEntry> allWeek;
  final DateTime now;
  final DateTime displayMonday;
  final WebUntisService service;

  const _WeekOverviewCard({
    required this.allWeek,
    required this.now,
    required this.displayMonday,
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

  List<_DayMarker> _dayMarkersForEntries(List<TimetableEntry> entries) {
    final seen = <_DayMarker>{};
    final groups = <_DayEntryGroup>[];
    final sortedEntries = [...entries]
      ..sort((a, b) => a.startTime.compareTo(b.startTime));

    for (final entry in sortedEntries) {
      var added = false;
      for (final group in groups) {
        if (entry.startTime < group.endTime &&
            entry.endTime > group.startTime) {
          group.add(entry);
          added = true;
          break;
        }
      }
      if (!added) {
        groups.add(_DayEntryGroup(entry));
      }
    }

    for (final group in groups) {
      final marker = _markerForSlot(group.entries);
      if (marker != null) seen.add(marker);
    }

    final markers = seen.toList()
      ..sort((a, b) => _dayMarkerPriority(a).compareTo(_dayMarkerPriority(b)));
    return markers;
  }

  _DayMarker? _markerForSlot(List<TimetableEntry> entries) {
    final cancelled = entries.where((e) => e.isCancelled).toList();
    final active = entries.where((e) => !e.isCancelled).toList();

    if (cancelled.isNotEmpty && active.isNotEmpty) {
      final additionalOnly = active
          .where((e) => e.isAdditional && !e.isSubstitution)
          .toList();
      final ambiguous = active
          .where((e) => e.isAdditional && e.isSubstitution)
          .toList();
      final substitutionOnly = active
          .where((e) => e.isSubstitution && !e.isAdditional)
          .toList();
      final chosen = additionalOnly.isNotEmpty
          ? additionalOnly.first
          : ambiguous.isNotEmpty
          ? ambiguous.first
          : substitutionOnly.isNotEmpty
          ? substitutionOnly.first
          : active.first;
      final marker = _markerForEntry(chosen);
      return marker ?? _DayMarker.substitution;
    }

    final markers = entries
        .map(_markerForEntry)
        .whereType<_DayMarker>()
        .toList();
    if (markers.isEmpty) return null;
    markers.sort(
      (a, b) => _dayMarkerPriority(a).compareTo(_dayMarkerPriority(b)),
    );
    return markers.last;
  }

  _DayMarker? _markerForEntry(TimetableEntry entry) {
    if (entry.isExam) return _DayMarker.exam;
    if (entry.isCancelled) return _DayMarker.cancelled;
    if (entry.isSubstitution) return _DayMarker.substitution;
    if (entry.isAdditional) return _DayMarker.additional;
    if (entry.subjectName.trim().isEmpty &&
        entry.lessonText.trim().isNotEmpty) {
      return _DayMarker.event;
    }
    if (entry.lessonText.trim().isNotEmpty) return _DayMarker.info;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final monday = displayMonday;
    final isNextWeek = now.weekday >= 6;
    final headerDate = isNextWeek ? monday : now;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(_DS.radius),
        border: Border.all(
          color: const Color.fromARGB(
            255,
            119,
            119,
            119,
          ).withValues(alpha: 0.18),
          width: 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _DS.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Center(
                  child: Icon(
                    CupertinoIcons.calendar,
                    size: 12,
                    color: _DS.accent,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isNextWeek ? 'Nächste Woche' : 'Diese Woche',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: context.appTextSecondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_weekdays[headerDate.weekday - 1]}, ${headerDate.day}. ${_months[headerDate.month - 1]}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: context.appTextTertiary,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
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
              final isHolidayDay =
                  dayEntries.isEmpty &&
                  (allWeek.isEmpty || allWeek.any((e) => e.date != dateInt));
              final markers = isHolidayDay
                  ? const [_DayMarker.holiday]
                  : _dayMarkersForEntries(dayEntries);
              final hasExam = markers.contains(_DayMarker.exam);
              final hasCancelled = markers.contains(_DayMarker.cancelled);

              return Expanded(
                child: Column(
                  children: [
                    Text(
                      _dayLabels[i],
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: isToday ? _DS.accent : context.appTextTertiary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: isToday ? _DS.accent : context.appCardAlt,
                        borderRadius: BorderRadius.circular(20),
                        border: !isToday
                            ? Border.all(
                                color: context.appBorder.withValues(alpha: 0.7),
                                width: 1,
                              )
                            : null,
                        boxShadow: isToday
                            ? [
                                BoxShadow(
                                  color: _DS.accent.withValues(alpha: 0.14),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: Center(
                        child: markers.isNotEmpty
                            ? _DayIconFan(markers: markers, isToday: isToday)
                            : Text(
                                '${day.day}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: isToday
                                      ? Colors.white
                                      : isPast
                                      ? context.appTextTertiary
                                      : context.appTextPrimary,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    if (hasCancelled && !hasExam)
                      Container(
                        width: 4,
                        height: 4,
                        decoration: BoxDecoration(
                          color: _DS.accentRed.withValues(alpha: 0.65),
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
          const SizedBox(height: 12),
          Text(
            '${allWeek.length} Std. diese Woche',
            style: TextStyle(fontSize: 10, color: context.appTextTertiary),
          ),
        ],
      ),
    );
  }
}

enum _DayMarker {
  exam,
  cancelled,
  substitution,
  additional,
  event,
  holiday,
  info,
}

int _dayMarkerPriority(_DayMarker marker) {
  switch (marker) {
    case _DayMarker.info:
      return 0;
    case _DayMarker.holiday:
      return 1;
    case _DayMarker.event:
      return 2;
    case _DayMarker.additional:
      return 3;
    case _DayMarker.substitution:
      return 4;
    case _DayMarker.cancelled:
      return 5;
    case _DayMarker.exam:
      return 6;
  }
}

class _DayEntryGroup {
  int startTime;
  int endTime;
  final List<TimetableEntry> entries;

  _DayEntryGroup(TimetableEntry entry)
    : startTime = entry.startTime,
      endTime = entry.endTime,
      entries = [entry];

  void add(TimetableEntry entry) {
    entries.add(entry);
    startTime = startTime < entry.startTime ? startTime : entry.startTime;
    endTime = endTime > entry.endTime ? endTime : entry.endTime;
  }
}

class _DayIconFan extends StatelessWidget {
  final List<_DayMarker> markers;
  final bool isToday;

  const _DayIconFan({required this.markers, required this.isToday});

  (IconData, Color) _styleFor(_DayMarker marker, BuildContext context) {
    switch (marker) {
      case _DayMarker.exam:
        return (CupertinoIcons.doc_text_fill, AppTheme.warning);
      case _DayMarker.cancelled:
        return (CupertinoIcons.xmark_octagon_fill, AppTheme.danger);
      case _DayMarker.substitution:
        return (CupertinoIcons.person_2_fill, AppTheme.orange);
      case _DayMarker.additional:
        return (CupertinoIcons.plus_app_fill, AppTheme.accent);
      case _DayMarker.event:
        return (CupertinoIcons.star_circle_fill, AppTheme.tint);
      case _DayMarker.holiday:
        return (CupertinoIcons.sun_max_fill, AppTheme.orange);
      case _DayMarker.info:
        return (CupertinoIcons.info_circle_fill, context.appTextSecondary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = markers.isNotEmpty ? [markers.last] : markers;
    final count = visible.length;

    if (count == 1) {
      final isHoliday = visible[0] == _DayMarker.holiday;
      final iconStyle = _styleFor(visible[0], context);
      final iconSize = isToday ? 17.3 : 16.5;
      final chipSize = iconSize + 5;
      return SizedBox(
        width: 38,
        height: 38,
        child: Center(
          child: Container(
            width: chipSize,
            height: chipSize,
            decoration: BoxDecoration(
              color: iconStyle.$2.withValues(alpha: isToday ? 0.95 : 0.90),
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.75),
                width: 0.8,
              ),
            ),
            child: isHoliday
                ? const Center(
                    child: Text('🏖️', style: TextStyle(fontSize: 14)),
                  )
                : Icon(iconStyle.$1, size: iconSize, color: Colors.white),
          ),
        ),
      );
    }

    final baseIconSize = count <= 2
        ? 16.5
        : count <= 4
        ? 15.0
        : count <= 6
        ? 13.5
        : 12.2;
    final iconSize = isToday ? baseIconSize + 0.8 : baseIconSize;
    const fanWidth = 38.0;
    const fanHeight = 38.0;
    final step = count <= 3
        ? 7.2
        : count <= 5
        ? 5.9
        : count <= 7
        ? 5.0
        : 4.4;
    final halfSpan = ((count - 1) * step) / 2;
    const arcDepth = 4.0;
    final centerFillWidth = count <= 2 ? 18.0 : (20.0 + (count - 2) * 1.6);
    final centerFillAlpha = isToday ? 0.30 : 0.24;
    final chipSize = iconSize + 5;

    final envelopeWidth = chipSize + (halfSpan * 2);
    final baseLeft = (fanWidth - envelopeWidth) / 2;

    double avgDy = 0;
    for (int i = 0; i < count; i++) {
      final n = (i / (count - 1)) * 2 - 1;
      avgDy += (n * n) * arcDepth;
    }
    avgDy /= count;
    final baseTop = fanHeight / 2 - chipSize / 2 - avgDy;

    final centerX = fanWidth / 2;
    final centerY = fanHeight / 2;

    return SizedBox(
      width: fanWidth,
      height: fanHeight,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: centerX - centerFillWidth / 2,
            top: centerY - (iconSize + 3) / 2,
            child: Container(
              width: centerFillWidth.clamp(18.0, 30.0),
              height: iconSize + 3,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: centerFillAlpha),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
          for (int i = 0; i < count; i++)
            Builder(
              builder: (_) {
                final normalized = (i / (count - 1)) * 2 - 1;
                final absNorm = normalized.abs();
                final curve = absNorm * absNorm;
                final dx = normalized * halfSpan;
                final dy = curve * arcDepth;
                final angle = normalized * 0.20;
                final iconStyle = _styleFor(visible[i], context);

                return Positioned(
                  left: baseLeft + halfSpan + dx,
                  top: baseTop + dy,
                  child: Transform.rotate(
                    angle: angle,
                    child: Container(
                      width: chipSize,
                      height: chipSize,
                      decoration: BoxDecoration(
                        color: iconStyle.$2.withValues(
                          alpha: isToday ? 0.95 : 0.90,
                        ),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.75),
                          width: 0.8,
                        ),
                      ),
                      child: Icon(
                        iconStyle.$1,
                        size: iconSize,
                        color: Colors.white,
                      ),
                    ),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  LOADING CARD
// ═══════════════════════════════════════════════════════════════════════════════

class _LoadingCard extends StatelessWidget {
  const _LoadingCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: BoxDecoration(
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Center(child: CupertinoActivityIndicator(radius: 12)),
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
        color: context.appSurface,
        borderRadius: BorderRadius.circular(14),
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
            style: TextStyle(color: context.appTextSecondary, fontSize: 12),
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
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  CARD ENTRY + REORDER LIST
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

class _CardReorderList extends StatefulWidget {
  final List<_CardEntry> cards;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _CardReorderList({required this.cards, required this.onReorder});

  @override
  State<_CardReorderList> createState() => _CardReorderListState();
}

class _CardReorderListState extends State<_CardReorderList> {
  int? _draggingIndex;

  void _startDrag(int index) {
    HapticFeedback.mediumImpact();
    setState(() => _draggingIndex = index);
  }

  void _endDrag() => setState(() => _draggingIndex = null);

  void _drop(int from, int to) {
    _endDrag();
    if (from != to) widget.onReorder(from, to);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Column(
      children: List.generate(widget.cards.length, (index) {
        final entry = widget.cards[index];
        final isDragging = _draggingIndex == index;

        return Padding(
          key: entry.key,
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
          child: LongPressDraggable<int>(
            data: index,
            delay: const Duration(milliseconds: 380),
            hapticFeedbackOnStart: true,
            onDragStarted: () => _startDrag(index),
            onDragEnd: (_) => _endDrag(),
            onDraggableCanceled: (_, _) => _endDrag(),
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
              onWillAcceptWithDetails: (d) => d.data != index,
              onLeave: (_) {},
              onAcceptWithDetails: (d) => _drop(d.data, index),
              builder: (context, candidates, _) {
                final isTarget = candidates.isNotEmpty;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  transform: Matrix4.diagonal3Values(
                    isDragging ? 0.97 : 1.0,
                    isDragging ? 0.97 : 1.0,
                    1.0,
                  ),
                  transformAlignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: isTarget
                        ? Border.all(
                            color: AppTheme.accent.withValues(alpha: 0.6),
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
