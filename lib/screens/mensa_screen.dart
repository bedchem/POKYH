import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'dart:ui';
import '../models/dish.dart';
import '../services/dish_service.dart';
import '../theme/app_theme.dart';

class MensaScreen extends StatefulWidget {
  const MensaScreen({super.key});

  @override
  State<MensaScreen> createState() => _MensaScreenState();
}

class _MensaScreenState extends State<MensaScreen> {
  final DishService _service = DishService();
  List<Dish> _dishes = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });

    final server = await _service.fetchFromServer();
    if (!mounted) return;

    if (server != null) {
      setState(() { _dishes = server; _loading = false; });
      return;
    }

    final cached = await _service.loadFromCache();
    if (!mounted) return;

    if (cached != null && cached.isNotEmpty) {
      setState(() { _dishes = cached; _loading = false; });
      return;
    }

    setState(() { _loading = false; _error = 'Keine Verbindung zum Server'; });
  }

  Map<DateTime, List<Dish>> get _grouped {
    final map = <DateTime, List<Dish>>{};
    for (final d in _dishes) {
      final key = DateTime(d.date.year, d.date.month, d.date.day);
      (map[key] ??= []).add(d);
    }
    return Map.fromEntries(
      map.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    );
  }

  List<MapEntry<DateTime, List<Dish>>> get _upcomingDays {
    final today = DateTime.now();
    final todayKey = DateTime(today.year, today.month, today.day);
    return _grouped.entries
        .where((e) => !e.key.isBefore(todayKey))
        .toList();
  }

  void _showDishDetail(BuildContext context, Dish dish) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _DishDetailSheet(dish: dish),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.accent,
        backgroundColor: AppTheme.surface,
        onRefresh: _load,
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
                    const Text('Mensa',
                        style: TextStyle(fontSize: 34, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary, letterSpacing: -0.5)),
                    if (!_loading && _error == null && _dishes.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_upcomingDays.length} Tage verfügbar',
                          style: const TextStyle(fontSize: 14, color: AppTheme.textSecondary),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),

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
                      Text('Menü wird geladen\u2026',
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
                      Container(
                        width: 56, height: 56,
                        decoration: BoxDecoration(
                          color: AppTheme.textTertiary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(CupertinoIcons.wifi_slash,
                            color: AppTheme.textTertiary, size: 26),
                      ),
                      const SizedBox(height: 16),
                      Text(_error!,
                          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                      const SizedBox(height: 14),
                      CupertinoButton(
                        color: AppTheme.accent,
                        borderRadius: BorderRadius.circular(10),
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                        minimumSize: Size.zero,
                        onPressed: _load,
                        child: const Text('Erneut versuchen',
                            style: TextStyle(fontSize: 14)),
                      ),
                    ],
                  ),
                ),
              )
            else if (_dishes.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(CupertinoIcons.tray, color: AppTheme.textTertiary, size: 36),
                      SizedBox(height: 12),
                      Text('Kein Menü verfügbar',
                          style: TextStyle(color: AppTheme.textSecondary, fontSize: 15)),
                    ],
                  ),
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (_, i) {
                      final entry = _upcomingDays[i];
                      return _DaySection(
                        date: entry.key,
                        dishes: entry.value,
                        onDishTap: (dish) => _showDishDetail(context, dish),
                      );
                    },
                    childCount: _upcomingDays.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Day Section ──────────────────────────────────────────────────────────────

class _DaySection extends StatelessWidget {
  final DateTime date;
  final List<Dish> dishes;
  final void Function(Dish) onDishTap;
  const _DaySection({required this.date, required this.dishes, required this.onDishTap});

  static const _weekdays = ['Montag', 'Dienstag', 'Mittwoch', 'Donnerstag', 'Freitag', 'Samstag', 'Sonntag'];
  static const _months = ['Jan', 'Feb', 'Mär', 'Apr', 'Mai', 'Jun',
    'Jul', 'Aug', 'Sep', 'Okt', 'Nov', 'Dez'];

  bool get _isToday {
    final now = DateTime.now();
    return date.year == now.year && date.month == now.month && date.day == now.day;
  }

  bool get _isTomorrow {
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    return date.year == tomorrow.year && date.month == tomorrow.month && date.day == tomorrow.day;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date header
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 10),
            child: Row(
              children: [
                if (_isToday)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text('Heute',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: Colors.white)),
                  )
                else if (_isTomorrow)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppTheme.accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Text('Morgen',
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: AppTheme.accent)),
                  ),
                if (_isToday || _isTomorrow) const SizedBox(width: 8),
                Text(
                  '${_weekdays[date.weekday - 1]}, ${date.day}. ${_months[date.month - 1]}',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: _isToday ? AppTheme.textPrimary : AppTheme.textSecondary,
                  ),
                ),
              ],
            ),
          ),

          // Dishes
          ...dishes.map((d) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _DishCard(dish: d, onTap: () => onDishTap(d)),
          )),
        ],
      ),
    );
  }
}

// ── Dish Card ────────────────────────────────────────────────────────────────

class _DishCard extends StatelessWidget {
  final Dish dish;
  final VoidCallback onTap;
  const _DishCard({required this.dish, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          borderRadius: BorderRadius.circular(16),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image with overlay
            if (dish.hasImage)
              Stack(
                children: [
                  SizedBox(
                    height: 160,
                    width: double.infinity,
                    child: Image.network(
                      dish.imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: AppTheme.card,
                        child: const Center(
                          child: Icon(CupertinoIcons.photo, color: AppTheme.textTertiary, size: 32),
                        ),
                      ),
                    ),
                  ),
                  // Gradient overlay at bottom of image
                  Positioned(
                    bottom: 0, left: 0, right: 0,
                    child: Container(
                      height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            AppTheme.surface.withValues(alpha: 0.8),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Tags on image
                  if (dish.isVegan || dish.isVegetarian)
                    Positioned(
                      top: 10, left: 10,
                      child: Row(
                        children: [
                          if (dish.isVegan)
                            _FloatingTag(label: 'Vegan', color: AppTheme.success),
                          if (dish.isVegetarian && !dish.isVegan)
                            _FloatingTag(label: 'Vegetarisch', color: AppTheme.tint),
                        ],
                      ),
                    ),
                ],
              ),

            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          dish.name('de'),
                          style: const TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(CupertinoIcons.chevron_right,
                          size: 14, color: AppTheme.textTertiary.withValues(alpha: 0.6)),
                    ],
                  ),

                  if (dish.hasCategory) ...[
                    const SizedBox(height: 4),
                    Text(
                      dish.category,
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary),
                    ),
                  ],

                  // Quick nutrition preview
                  if (dish.hasNutrition) ...[
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (dish.calories > 0)
                          _NutritionChip(
                              icon: CupertinoIcons.flame_fill,
                              value: '${dish.calories} kcal',
                              color: AppTheme.orange),
                        if (dish.protein > 0) ...[
                          const SizedBox(width: 6),
                          _NutritionChip(
                              icon: CupertinoIcons.bolt_fill,
                              value: '${dish.protein.toStringAsFixed(0)}g Protein',
                              color: AppTheme.accent),
                        ],
                        if (dish.fat > 0) ...[
                          const SizedBox(width: 6),
                          _NutritionChip(
                              icon: CupertinoIcons.drop_fill,
                              value: '${dish.fat.toStringAsFixed(0)}g Fett',
                              color: AppTheme.warning),
                        ],
                      ],
                    ),
                  ],

                  // Tags if no image
                  if (!dish.hasImage && (dish.isVegan || dish.isVegetarian)) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (dish.isVegan)
                          _TagBadge(label: 'Vegan', color: AppTheme.success),
                        if (dish.isVegetarian && !dish.isVegan)
                          _TagBadge(label: 'Vegetarisch', color: AppTheme.tint),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Dish Detail Bottom Sheet ─────────────────────────────────────────────────

class _DishDetailSheet extends StatelessWidget {
  final Dish dish;
  const _DishDetailSheet({required this.dish});

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      constraints: BoxConstraints(maxHeight: screenHeight * 0.88),
      decoration: const BoxDecoration(
        color: AppTheme.bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Container(
              width: 36, height: 5,
              decoration: BoxDecoration(
                color: AppTheme.textTertiary.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Hero Image ──
                  if (dish.hasImage)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SizedBox(
                        height: 200,
                        width: double.infinity,
                        child: Image.network(
                          dish.imageUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: AppTheme.card,
                            child: const Center(
                              child: Icon(CupertinoIcons.photo,
                                  color: AppTheme.textTertiary, size: 40),
                            ),
                          ),
                        ),
                      ),
                    ),

                  if (dish.hasImage) const SizedBox(height: 20),

                  // ── Tags ──
                  if (dish.isVegan || dish.isVegetarian)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          if (dish.isVegan)
                            _DetailTag(label: 'Vegan', color: AppTheme.success,
                                icon: CupertinoIcons.leaf_arrow_circlepath),
                          if (dish.isVegetarian && !dish.isVegan)
                            _DetailTag(label: 'Vegetarisch', color: AppTheme.tint,
                                icon: CupertinoIcons.leaf_arrow_circlepath),
                        ],
                      ),
                    ),

                  // ── Title ──
                  Text(
                    dish.name('de'),
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w700,
                      color: AppTheme.textPrimary,
                      letterSpacing: -0.5,
                    ),
                  ),

                  if (dish.hasCategory) ...[
                    const SizedBox(height: 4),
                    Text(
                      dish.category,
                      style: const TextStyle(fontSize: 15, color: AppTheme.textSecondary),
                    ),
                  ],

                  // ── Description ──
                  if (dish.hasDescription()) ...[
                    const SizedBox(height: 16),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: AppTheme.surface,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(CupertinoIcons.text_quote,
                                  size: 14, color: AppTheme.textSecondary),
                              SizedBox(width: 6),
                              Text('Beschreibung',
                                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                                      color: AppTheme.textSecondary)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            dish.description('de'),
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppTheme.textPrimary,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  // ── Nutrition Section ──
                  if (dish.hasNutrition) ...[
                    const SizedBox(height: 20),
                    const Text('Nährwerte',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 12),

                    // Main nutrition cards
                    Row(
                      children: [
                        if (dish.calories > 0)
                          Expanded(
                            child: _NutritionCard(
                              icon: CupertinoIcons.flame_fill,
                              label: 'Kalorien',
                              value: '${dish.calories}',
                              unit: 'kcal',
                              color: AppTheme.orange,
                            ),
                          ),
                        if (dish.calories > 0 && dish.protein > 0)
                          const SizedBox(width: 10),
                        if (dish.protein > 0)
                          Expanded(
                            child: _NutritionCard(
                              icon: CupertinoIcons.bolt_fill,
                              label: 'Protein',
                              value: dish.protein.toStringAsFixed(1),
                              unit: 'g',
                              color: AppTheme.accent,
                            ),
                          ),
                        if ((dish.calories > 0 || dish.protein > 0) && dish.fat > 0)
                          const SizedBox(width: 10),
                        if (dish.fat > 0)
                          Expanded(
                            child: _NutritionCard(
                              icon: CupertinoIcons.drop_fill,
                              label: 'Fett',
                              value: dish.fat.toStringAsFixed(1),
                              unit: 'g',
                              color: AppTheme.warning,
                            ),
                          ),
                      ],
                    ),

                    // Nutrition bar visual
                    if (dish.calories > 0 && dish.protein > 0 && dish.fat > 0) ...[
                      const SizedBox(height: 16),
                      _NutritionBar(dish: dish),
                    ],
                  ],

                  // ── Allergens ──
                  if (dish.allergens.isNotEmpty) ...[
                    const SizedBox(height: 20),
                    const Text('Allergene',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary)),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: dish.allergens.map((a) => Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: AppTheme.danger.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppTheme.danger.withValues(alpha: 0.15)),
                        ),
                        child: Text(a,
                            style: const TextStyle(fontSize: 13, color: AppTheme.danger,
                                fontWeight: FontWeight.w500)),
                      )).toList(),
                    ),
                  ],

                  // ── Price ──
                  if (dish.price > 0) ...[
                    const SizedBox(height: 20),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: AppTheme.accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.15)),
                      ),
                      child: Row(
                        children: [
                          Icon(CupertinoIcons.tag_fill,
                              size: 18, color: AppTheme.accent.withValues(alpha: 0.7)),
                          const SizedBox(width: 10),
                          const Text('Preis',
                              style: TextStyle(fontSize: 15, color: AppTheme.textSecondary)),
                          const Spacer(),
                          Text(
                            '\u20AC ${dish.price.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Nutrition Card ───────────────────────────────────────────────────────────

class _NutritionCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String unit;
  final Color color;

  const _NutritionCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.unit,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(value,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700,
                      color: color, fontFeatures: const [FontFeature.tabularFigures()])),
              const SizedBox(width: 2),
              Text(unit,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500,
                      color: color.withValues(alpha: 0.7))),
            ],
          ),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 12, color: AppTheme.textTertiary)),
        ],
      ),
    );
  }
}

// ── Nutrition Bar ────────────────────────────────────────────────────────────

class _NutritionBar extends StatelessWidget {
  final Dish dish;
  const _NutritionBar({required this.dish});

  @override
  Widget build(BuildContext context) {
    // Estimate carbs from calories (approximate)
    final proteinCal = dish.protein * 4;
    final fatCal = dish.fat * 9;
    final carbsCal = (dish.calories - proteinCal - fatCal).clamp(0, dish.calories.toDouble());
    final total = proteinCal + fatCal + carbsCal;
    if (total <= 0) return const SizedBox.shrink();

    final proteinFrac = proteinCal / total;
    final fatFrac = fatCal / total;
    final carbsFrac = carbsCal / total;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Makroverteilung',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                  color: AppTheme.textSecondary)),
          const SizedBox(height: 10),
          // Bar
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: SizedBox(
              height: 10,
              child: Row(
                children: [
                  Expanded(
                    flex: (proteinFrac * 100).round().clamp(1, 100),
                    child: Container(color: AppTheme.accent),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: (fatFrac * 100).round().clamp(1, 100),
                    child: Container(color: AppTheme.warning),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    flex: (carbsFrac * 100).round().clamp(1, 100),
                    child: Container(color: AppTheme.success),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          // Legend
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _MacroLegend(
                  color: AppTheme.accent,
                  label: 'Protein',
                  value: '${(proteinFrac * 100).round()}%'),
              _MacroLegend(
                  color: AppTheme.warning,
                  label: 'Fett',
                  value: '${(fatFrac * 100).round()}%'),
              _MacroLegend(
                  color: AppTheme.success,
                  label: 'Kohlenhydrate',
                  value: '${(carbsFrac * 100).round()}%'),
            ],
          ),
        ],
      ),
    );
  }
}

class _MacroLegend extends StatelessWidget {
  final Color color;
  final String label;
  final String value;
  const _MacroLegend({required this.color, required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        Text('$label $value',
            style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ── Shared Widgets ───────────────────────────────────────────────────────────

class _FloatingTag extends StatelessWidget {
  final String label;
  final Color color;
  const _FloatingTag({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.25),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(label,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ),
      ),
    );
  }
}

class _NutritionChip extends StatelessWidget {
  final IconData icon;
  final String value;
  final Color color;
  const _NutritionChip({required this.icon, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 11, color: color),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: color)),
        ],
      ),
    );
  }
}

class _TagBadge extends StatelessWidget {
  final String label;
  final Color color;
  const _TagBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color)),
    );
  }
}

class _DetailTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData icon;
  const _DetailTag({required this.label, required this.color, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
