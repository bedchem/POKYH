import 'package:flutter/cupertino.dart';
import '../l10n/app_localizations.dart';
import '../models/dish.dart';
import '../widgets/tag_chip.dart';
import 'settings_screen.dart';

class DetailScreen extends StatefulWidget {
  final Dish dish;
  final AppSettings settings;

  const DetailScreen({super.key, required this.dish, required this.settings});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeController;
  late final Animation<double> _fadeAnimation;

  Dish get dish => widget.dish;

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = AppLocalizations.of(context);
    final mediaQuery = MediaQuery.of(context);

    return CupertinoPageScaffold(
      backgroundColor: CupertinoColors.systemGroupedBackground,
      navigationBar: CupertinoNavigationBar(
        previousPageTitle: l.get('menu'),
        backgroundColor: CupertinoColors.systemGroupedBackground
            .resolveFrom(context)
            .withValues(alpha: 0.85),
        border: null,
      ),
      child: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Hero image or placeholder
                  SizedBox(
                    height: dish.hasImage ? 320 : 160,
                    width: double.infinity,
                    child: Hero(
                      tag: 'dish-${dish.id}',
                      child: dish.hasImage
                          ? Image.network(
                              dish.imageUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, progress) {
                                if (progress == null) return child;
                                return _buildImagePlaceholder(context);
                              },
                              errorBuilder: (_, _, _) =>
                                  _buildImagePlaceholder(context),
                            )
                          : _buildImagePlaceholder(context),
                    ),
                  ),

                  // Fade-in content
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name
                          Text(
                            dish.name(l.langCode),
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.5,
                              color: CupertinoColors.label.resolveFrom(context),
                            ),
                          ),

                          // Category + Rating row (only if data exists)
                          if (dish.hasCategory || dish.rating > 0) ...[
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                if (dish.hasCategory) ...[
                                  Icon(
                                    CupertinoIcons.tag,
                                    size: 14,
                                    color: CupertinoColors.secondaryLabel
                                        .resolveFrom(context),
                                  ),
                                  const SizedBox(width: 5),
                                  Text(
                                    dish.category,
                                    style: TextStyle(
                                      fontSize: 15,
                                      color: CupertinoColors.secondaryLabel
                                          .resolveFrom(context),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                if (dish.rating > 0) ...[
                                  const Icon(
                                    CupertinoIcons.star_fill,
                                    size: 16,
                                    color: CupertinoColors.systemYellow,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    dish.rating.toStringAsFixed(1),
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: CupertinoColors.label
                                          .resolveFrom(context),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],

                          // Date
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Icon(
                                CupertinoIcons.calendar,
                                size: 14,
                                color: CupertinoColors.activeBlue,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                '${l.weekdayLong(dish.date.weekday)}, ${dish.date.day}. ${l.monthName(dish.date.month)} ${dish.date.year}',
                                style: TextStyle(
                                  fontSize: 15,
                                  color: CupertinoColors.secondaryLabel
                                      .resolveFrom(context),
                                ),
                              ),
                            ],
                          ),

                          // Nutrition metadata pills (always shown)
                          const SizedBox(height: 20),
                          _buildMetadataRow(context, l),

                          // Tags
                          if (dish.tags.isNotEmpty) ...[
                            const SizedBox(height: 20),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: dish.tags
                                  .map((tag) => TagChip(label: tag))
                                  .toList(),
                            ),
                          ],

                          // Description
                          if (dish.hasDescription(l.langCode)) ...[
                            const SizedBox(height: 24),
                            Text(
                              l.get('description'),
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color:
                                    CupertinoColors.label.resolveFrom(context),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              dish.description(l.langCode),
                              style: TextStyle(
                                fontSize: 16,
                                height: 1.5,
                                color:
                                    CupertinoColors.label.resolveFrom(context),
                              ),
                            ),
                          ],

                          // Allergens
                          if (dish.allergens.isNotEmpty && widget.settings.showAllergens) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                const Icon(
                                  CupertinoIcons.exclamationmark_triangle,
                                  size: 16,
                                  color: CupertinoColors.systemRed,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l.get('allergens'),
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: CupertinoColors.label
                                        .resolveFrom(context),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: dish.allergens.map((allergen) {
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: CupertinoColors.systemRed
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: CupertinoColors.systemRed
                                          .withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Text(
                                    allergen,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w500,
                                      color: CupertinoColors.systemRed,
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ],

                          // Dietary badges
                          if (dish.isVegetarian || dish.isVegan) ...[
                            const SizedBox(height: 24),
                            Row(
                              children: [
                                if (dish.isVegan)
                                  _buildDietaryBadge(
                                    context,
                                    icon: CupertinoIcons.leaf_arrow_circlepath,
                                    label: l.get('vegan'),
                                  )
                                else if (dish.isVegetarian)
                                  _buildDietaryBadge(
                                    context,
                                    icon: CupertinoIcons.leaf_arrow_circlepath,
                                    label: l.get('vegetarian'),
                                  ),
                              ],
                            ),
                          ],

                          SizedBox(height: mediaQuery.padding.bottom + 16),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePlaceholder(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CupertinoColors.systemGrey5.resolveFrom(context),
            CupertinoColors.systemGrey4.resolveFrom(context),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          CupertinoIcons.square_favorites_alt,
          size: 56,
          color: CupertinoColors.systemGrey2.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _buildMetadataRow(BuildContext context, AppLocalizations l) {
    final s = widget.settings;
    return Row(
      children: [
        // Fat pill (replaces prep time)
        Expanded(
          child: _buildMetadataPill(
            context,
            icon: CupertinoIcons.drop,
            value: dish.fat > 0
                ? '${dish.fat.toStringAsFixed(1)}g'
                : 'n/a',
            unit: l.get('fat'),
            isBold: true,
          ),
        ),
        if (s.showCalories) ...[
          const SizedBox(width: 12),
          Expanded(
            child: _buildMetadataPill(
              context,
              icon: CupertinoIcons.flame,
              value: dish.calories > 0 ? '${dish.calories}' : 'n/a',
              unit: l.get('kcal'),
            ),
          ),
        ],
        // Protein pill (replaces price)
        const SizedBox(width: 12),
        Expanded(
          child: _buildMetadataPill(
            context,
            icon: CupertinoIcons.bolt,
            value: dish.protein > 0
                ? '${dish.protein.toStringAsFixed(1)}g'
                : 'n/a',
            unit: l.get('protein'),
          ),
        ),
      ],
    );
  }

  Widget _buildMetadataPill(
    BuildContext context, {
    required IconData icon,
    required String value,
    required String unit,
    bool isBold = false,
  }) {
    final isNA = value == 'n/a';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: CupertinoColors.systemBackground.resolveFrom(context),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Icon(icon, size: 20, color: CupertinoColors.activeBlue),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 17,
              fontWeight: isBold ? FontWeight.w800 : FontWeight.w700,
              color: isNA
                  ? CupertinoColors.tertiaryLabel.resolveFrom(context)
                  : CupertinoColors.label.resolveFrom(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            unit,
            style: TextStyle(
              fontSize: 12,
              color: CupertinoColors.secondaryLabel.resolveFrom(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDietaryBadge(
    BuildContext context, {
    required IconData icon,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: CupertinoColors.systemGreen),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: CupertinoColors.systemGreen,
            ),
          ),
        ],
      ),
    );
  }
}
