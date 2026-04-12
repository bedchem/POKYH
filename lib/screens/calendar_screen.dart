import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../l10n/app_localizations.dart';
import '../models/dish.dart';
import 'detail_screen.dart';
import 'settings_screen.dart';

class CalendarScreen extends StatefulWidget {
  final List<Dish> dishes;
  final AppSettings settings;

  const CalendarScreen({super.key, required this.dishes, required this.settings});

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen>
    with SingleTickerProviderStateMixin {
  late DateTime _currentMonth;
  DateTime? _selectedDate;
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _currentMonth = DateTime(now.year, now.month, 1);
    _selectedDate = DateTime(now.year, now.month, now.day);
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  Map<DateTime, List<Dish>> get _dishesByDate {
    final map = <DateTime, List<Dish>>{};
    for (final dish in widget.dishes) {
      final key = DateTime(dish.date.year, dish.date.month, dish.date.day);
      map.putIfAbsent(key, () => []).add(dish);
    }
    return map;
  }

  List<Dish> _dishesForDate(DateTime date) {
    final key = DateTime(date.year, date.month, date.day);
    return _dishesByDate[key] ?? [];
  }

  bool _isToday(DateTime date) {
    final now = DateTime.now();
    return date.year == now.year &&
        date.month == now.month &&
        date.day == now.day;
  }

  bool _isSelected(DateTime date) {
    if (_selectedDate == null) return false;
    return date.year == _selectedDate!.year &&
        date.month == _selectedDate!.month &&
        date.day == _selectedDate!.day;
  }

  void _goToPrevious() {
    _fadeController.reverse().then((_) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month - 1, 1);
        _selectedDate = null;
      });
      _fadeController.forward();
    });
  }

  void _goToNext() {
    _fadeController.reverse().then((_) {
      setState(() {
        _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);
        _selectedDate = null;
      });
      _fadeController.forward();
    });
  }

  void _goToToday() {
    final now = DateTime.now();
    _fadeController.reverse().then((_) {
      setState(() {
        _currentMonth = DateTime(now.year, now.month, 1);
        _selectedDate = DateTime(now.year, now.month, now.day);
      });
      _fadeController.forward();
    });
  }

  void _selectDate(DateTime date) {
    setState(() => _selectedDate = date);
  }

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
            largeTitle: Text(l.get('calendar')),
            border: null,
            trailing: CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: _goToToday,
              child: Text(
                l.get('today'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                children: [
                  _buildMonthHeader(context, l),
                  _buildWeekdayHeaders(context, l),
                  _buildCalendarGrid(context, l),
                  if (_selectedDate != null) _buildSelectedDayDetail(context, l),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Month navigation header ───────────────────────────────────────────

  Widget _buildMonthHeader(BuildContext context, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            onPressed: _goToPrevious,
            child: const Icon(CupertinoIcons.chevron_left, size: 18),
          ),
          Expanded(
            child: Center(
              child: Text(
                '${l.monthName(_currentMonth.month)} ${_currentMonth.year}',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: CupertinoColors.label.resolveFrom(context),
                ),
              ),
            ),
          ),
          CupertinoButton(
            padding: const EdgeInsets.all(8),
            onPressed: _goToNext,
            child: const Icon(CupertinoIcons.chevron_right, size: 18),
          ),
        ],
      ),
    );
  }

  // ── Weekday column headers ────────────────────────────────────────────

  Widget _buildWeekdayHeaders(BuildContext context, AppLocalizations l) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: List.generate(7, (i) {
          final isWeekend = i >= 5;
          return Expanded(
            child: Center(
              child: Text(
                l.weekdayShort(i + 1),
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isWeekend
                      ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                      : CupertinoColors.secondaryLabel.resolveFrom(context),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── Calendar grid with Apple-style squares ────────────────────────────

  Widget _buildCalendarGrid(BuildContext context, AppLocalizations l) {
    final firstDay = DateTime(_currentMonth.year, _currentMonth.month, 1);
    final lastDay = DateTime(_currentMonth.year, _currentMonth.month + 1, 0);
    final firstWeekday = firstDay.weekday; // 1=Mon
    final daysInMonth = lastDay.day;
    final totalSlots = firstWeekday - 1 + daysInMonth;
    final rows = (totalSlots / 7).ceil();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        children: List.generate(rows, (row) {
          return Row(
            children: List.generate(7, (col) {
              final slotIndex = row * 7 + col;
              final dayOffset = slotIndex - (firstWeekday - 1);

              if (dayOffset < 0 || dayOffset >= daysInMonth) {
                return const Expanded(child: SizedBox(height: 60));
              }

              final date = DateTime(
                _currentMonth.year,
                _currentMonth.month,
                dayOffset + 1,
              );
              return Expanded(child: _buildDayCell(context, date));
            }),
          );
        }),
      ),
    );
  }

  Widget _buildDayCell(BuildContext context, DateTime date) {
    final isToday = _isToday(date);
    final isSelected = _isSelected(date);
    final dishes = _dishesForDate(date);
    final hasDishes = dishes.isNotEmpty;
    final isWeekend = date.weekday >= 6;

    return GestureDetector(
      onTap: () => _selectDate(date),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 60,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: isSelected
              ? CupertinoColors.activeBlue
              : hasDishes
                  ? CupertinoColors.systemBackground.resolveFrom(context)
                  : null,
          borderRadius: BorderRadius.circular(12),
          border: isToday && !isSelected
              ? Border.all(
                  color: CupertinoColors.activeBlue,
                  width: 2,
                )
              : null,
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: CupertinoColors.activeBlue.withValues(alpha: 0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: isToday || isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? CupertinoColors.white
                    : isWeekend
                        ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                        : CupertinoColors.label.resolveFrom(context),
              ),
            ),
            const SizedBox(height: 3),
            if (hasDishes)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  for (var i = 0; i < dishes.length && i < 3; i++)
                    Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 1.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isSelected
                            ? CupertinoColors.white
                            : CupertinoColors.activeBlue,
                      ),
                    ),
                ],
              )
            else
              const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  // ── Selected day detail panel ─────────────────────────────────────────

  Widget _buildSelectedDayDetail(BuildContext context, AppLocalizations l) {
    final dishes = _dishesForDate(_selectedDate!);
    final isToday = _isToday(_selectedDate!);

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeInOut,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Day label
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: CupertinoColors.systemBackground.resolveFrom(context),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(14),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isToday
                        ? CupertinoIcons.calendar_today
                        : CupertinoIcons.calendar,
                    size: 16,
                    color: CupertinoColors.activeBlue,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${l.weekdayLong(_selectedDate!.weekday)}, ${_selectedDate!.day}. ${l.monthName(_selectedDate!.month)}',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.label.resolveFrom(context),
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: CupertinoColors.activeBlue,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        l.get('today'),
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: CupertinoColors.white,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Dishes or empty
            if (dishes.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 32),
                decoration: BoxDecoration(
                  color: CupertinoColors.systemBackground.resolveFrom(context),
                  borderRadius: const BorderRadius.vertical(
                    bottom: Radius.circular(14),
                  ),
                ),
                child: Column(
                  children: [
                    Icon(
                      CupertinoIcons.moon_zzz,
                      size: 32,
                      color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l.get('no_dish_planned'),
                      style: TextStyle(
                        fontSize: 15,
                        color: CupertinoColors.tertiaryLabel.resolveFrom(context),
                      ),
                    ),
                  ],
                ),
              )
            else
              ...dishes.asMap().entries.map((entry) {
                final i = entry.key;
                final dish = entry.value;
                final isLast = i == dishes.length - 1;
                return _buildDishCard(context, dish, isLast, l.langCode);
              }),
          ],
        ),
      ),
    );
  }

  Widget _buildDishCard(BuildContext context, Dish dish, bool isLast, String lang) {
    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(
          CupertinoPageRoute(
            builder: (_) => DetailScreen(dish: dish, settings: widget.settings),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemBackground.resolveFrom(context),
          borderRadius: isLast
              ? const BorderRadius.vertical(bottom: Radius.circular(14))
              : null,
        ),
        child: Column(
          children: [
            // Large image
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 180,
                  width: double.infinity,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Hero(
                        tag: 'dish-${dish.id}',
                        child: dish.hasImage
                            ? Image.network(
                                dish.imageUrl,
                                fit: BoxFit.cover,
                                loadingBuilder: (context, child, progress) {
                                  if (progress == null) return child;
                                  return Container(
                                    color: CupertinoColors.systemGrey5
                                        .resolveFrom(context),
                                    child: const Center(
                                      child: CupertinoActivityIndicator(),
                                    ),
                                  );
                                },
                                errorBuilder: (_, _, _) => Container(
                                  color:
                                      CupertinoColors.systemGrey5.resolveFrom(context),
                                  child: const Icon(CupertinoIcons.photo, size: 32),
                                ),
                              )
                            : Container(
                                color: CupertinoColors.systemGrey5.resolveFrom(context),
                                child: Center(
                                  child: Icon(
                                    CupertinoIcons.square_favorites_alt,
                                    size: 32,
                                    color: CupertinoColors.systemGrey3.resolveFrom(context),
                                  ),
                                ),
                              ),
                      ),
                      // Gradient overlay
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0x00000000),
                                Color(0x00000000),
                                Color(0xAA000000),
                              ],
                              stops: [0.0, 0.5, 1.0],
                            ),
                          ),
                        ),
                      ),
                      // Frosted pill (only if prepTime > 0)
                      if (dish.prepTime > 0)
                        Positioned(
                          top: 10,
                          right: 10,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: BackdropFilter(
                              filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 5,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0x40FFFFFF),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(
                                      CupertinoIcons.clock,
                                      size: 12,
                                      color: CupertinoColors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      '${dish.prepTime} min',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                        color: CupertinoColors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      // Title overlay
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Text(
                          dish.name(lang),
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: CupertinoColors.white,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Info row below image
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
              child: Row(
                children: [
                  if (dish.hasCategory) ...[
                    Icon(
                      CupertinoIcons.tag,
                      size: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(width: 5),
                    Text(
                      dish.category,
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                  ],
                  const Spacer(),
                  if (dish.calories > 0 && widget.settings.showCalories) ...[
                    Icon(
                      CupertinoIcons.flame,
                      size: 13,
                      color: CupertinoColors.secondaryLabel.resolveFrom(context),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      '${dish.calories} kcal',
                      style: TextStyle(
                        fontSize: 14,
                        color: CupertinoColors.secondaryLabel.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  if (dish.rating > 0) ...[
                    const Icon(
                      CupertinoIcons.star_fill,
                      size: 13,
                      color: CupertinoColors.systemYellow,
                    ),
                    const SizedBox(width: 3),
                    Text(
                      dish.rating.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: CupertinoColors.label.resolveFrom(context),
                      ),
                    ),
                    const SizedBox(width: 8),
                  ],
                  Icon(
                    CupertinoIcons.chevron_right,
                    size: 14,
                    color: CupertinoColors.systemGrey3.resolveFrom(context),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
