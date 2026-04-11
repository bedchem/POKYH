import 'package:flutter/cupertino.dart';
import '../l10n/app_localizations.dart';
import '../models/dish.dart';
import '../screens/settings_screen.dart';
import '../widgets/dish_card.dart';
import '../widgets/error_view.dart';
import '../widgets/loading_indicator.dart';
import 'detail_screen.dart';

class HomeScreen extends StatefulWidget {
  final List<Dish> dishes;
  final bool isLoading;
  final String? error;
  final VoidCallback onRefresh;
  final AppSettings settings;

  const HomeScreen({
    super.key,
    required this.dishes,
    required this.isLoading,
    this.error,
    required this.onRefresh,
    required this.settings,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<DateTime, List<Dish>> _dishesByDate = const {};

  @override
  void initState() {
    super.initState();
    _rebuildDishIndex();
  }

  @override
  void didUpdateWidget(covariant HomeScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.dishes, widget.dishes)) {
      _rebuildDishIndex();
    }
  }

  DateTime _normalizeDate(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  void _rebuildDishIndex() {
    final grouped = <DateTime, List<Dish>>{};
    for (final dish in widget.dishes) {
      final key = _normalizeDate(dish.date);
      grouped.putIfAbsent(key, () => <Dish>[]).add(dish);
    }
    _dishesByDate = grouped;
  }

  // ── Week helpers ─────────────────────────────────────────────────────

  DateTime get _weekStart {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day - (now.weekday - 1));
  }

  List<DateTime> get _weekDays {
    final start = _weekStart;
    return List.generate(7, (i) => start.add(Duration(days: i)));
  }

  /// Week days sorted so today (or next day with dishes) is first
  List<DateTime> get _sortedWeekDays {
    final days = _weekDays;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // Find the index of today or the next day with dishes
    int startIndex = days.indexWhere((d) =>
        !d.isBefore(today) && _dishesForDate(d).isNotEmpty);

    // If no future day has dishes, fall back to today's index
    if (startIndex < 0) {
      startIndex = days.indexWhere((d) => !d.isBefore(today));
    }
    if (startIndex < 0) startIndex = 0;

    return [...days.sublist(startIndex), ...days.sublist(0, startIndex)];
  }

  List<Dish> _dishesForDate(DateTime date) {
    return _dishesByDate[_normalizeDate(date)] ?? const [];
  }

  List<Dish> get _weekDishes {
    final result = <Dish>[];
    for (final day in _weekDays) {
      result.addAll(_dishesForDate(day));
    }
    return result;
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  void _navigateToDetail(Dish dish) {
    Navigator.of(context).push(
      CupertinoPageRoute(
        builder: (_) => DetailScreen(dish: dish, settings: widget.settings),
      ),
    );
  }

  String _weekRangeLabel(AppLocalizations l) {
    final days = _weekDays;
    final start = days.first;
    final end = days.last;
    if (start.month == end.month) {
      return '${start.day}–${end.day} ${l.monthName(start.month)}';
    }
    return '${start.day} ${l.monthName(start.month)} – ${end.day} ${l.monthName(end.month)}';
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(
          parent: AlwaysScrollableScrollPhysics(),
        ),
        slivers: [
          CupertinoSliverNavigationBar(
            largeTitle: Text(l.get('menu')),
            border: null,
          ),
          CupertinoSliverRefreshControl(
            onRefresh: () async => widget.onRefresh(),
          ),
          if (widget.isLoading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: LoadingIndicator(),
            )
          else if (widget.error != null)
            SliverFillRemaining(
              hasScrollBody: false,
              child: ErrorView(
                message: widget.error!,
                onRetry: widget.onRefresh,
              ),
            )
          else ...[
            // Week header
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    Icon(
                      CupertinoIcons.calendar_today,
                      size: 16,
                      color: CupertinoColors.activeBlue,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l.get('this_week'),
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.activeBlue,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      _weekRangeLabel(l),
                      style: TextStyle(
                        fontSize: 13,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Week content
            if (_weekDishes.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _buildEmptyWeekState(l),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final date = _sortedWeekDays[index];
                      final dishes = _dishesForDate(date);
                      return _FadeInItem(
                        index: index,
                        child: _buildDaySection(context, date, dishes, l),
                      );
                    },
                    childCount: _sortedWeekDays.length,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  // ── Day section ──────────────────────────────────────────────────────

  Widget _buildDaySection(
    BuildContext context,
    DateTime date,
    List<Dish> dishes,
    AppLocalizations l,
  ) {
    final isToday = _isToday(date);

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Day header
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isToday
                        ? CupertinoColors.activeBlue
                        : CupertinoColors.systemGrey5.resolveFrom(context),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      '${date.day}',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: isToday
                            ? CupertinoColors.white
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.weekdayLong(date.weekday),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: isToday
                            ? CupertinoColors.activeBlue
                            : CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    if (isToday)
                      Text(
                        l.get('today'),
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: CupertinoColors.activeBlue,
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),

          // Dishes or empty
          if (dishes.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground.resolveFrom(context),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      CupertinoIcons.moon_zzz,
                      size: 16,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      l.get('no_dish_planned'),
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ...dishes.map((dish) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: isToday
                      ? SizedBox(
                          height: 220,
                          child: DishCard(
                            dish: dish,
                            lang: l.langCode,
                            onTap: () => _navigateToDetail(dish),
                          ),
                        )
                      : _buildCompactDishRow(context, dish, l.langCode),
                )),
        ],
      ),
    );
  }

  // ── Compact row for non-today dishes ─────────────────────────────────

  Widget _buildCompactDishRow(BuildContext context, Dish dish, String lang) {
    return GestureDetector(
      onTap: () => _navigateToDetail(dish),
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: SizedBox(
                width: 80,
                height: 80,
                child: dish.hasImage
                    ? Image.network(
                        dish.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return _compactPlaceholder(context);
                        },
                        errorBuilder: (_, __, ___) => _compactPlaceholder(context),
                      )
                    : _compactPlaceholder(context),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dish.name(lang),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (dish.hasCategory || dish.isVegetarian) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (dish.hasCategory) ...[
                            Icon(
                              CupertinoIcons.tag,
                              size: 12,
                              color: CupertinoColors.secondaryLabel.resolveFrom(context),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                dish.category,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: CupertinoColors.secondaryLabel.resolveFrom(context),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          if (dish.isVegetarian) ...[
                            if (dish.hasCategory) const SizedBox(width: 10),
                            Icon(
                              CupertinoIcons.leaf_arrow_circlepath,
                              size: 12,
                              color: CupertinoColors.systemGreen,
                            ),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Icon(
                CupertinoIcons.chevron_right,
                size: 14,
                color: CupertinoColors.systemGrey3.resolveFrom(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _compactPlaceholder(BuildContext context) {
    return Container(
      color: CupertinoColors.systemGrey5.resolveFrom(context),
      child: Center(
        child: Icon(
          CupertinoIcons.square_favorites_alt,
          size: 24,
          color: CupertinoColors.systemGrey3.resolveFrom(context),
        ),
      ),
    );
  }

  // ── Empty states ─────────────────────────────────────────────────────

  Widget _buildEmptyWeekState(AppLocalizations l) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            CupertinoIcons.calendar_badge_minus,
            size: 48,
            color: CupertinoColors.systemGrey.resolveFrom(context),
          ),
          const SizedBox(height: 16),
          Text(
            l.get('no_dishes_this_week'),
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Staggered fade-in animation ──────────────────────────────────────────

class _FadeInItem extends StatefulWidget {
  final int index;
  final Widget child;

  const _FadeInItem({required this.index, required this.child});

  @override
  State<_FadeInItem> createState() => _FadeInItemState();
}

class _FadeInItemState extends State<_FadeInItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _slide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _slide = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    Future.delayed(Duration(milliseconds: 50 * widget.index), () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(
        position: _slide,
        child: widget.child,
      ),
    );
  }
}
