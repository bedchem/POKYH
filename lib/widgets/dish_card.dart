import 'dart:ui';
import 'package:flutter/cupertino.dart';
import '../models/dish.dart';

class DishCard extends StatefulWidget {
  final Dish dish;
  final VoidCallback onTap;
  final String lang;

  const DishCard({
    super.key,
    required this.dish,
    required this.onTap,
    this.lang = 'de',
  });

  @override
  State<DishCard> createState() => _DishCardState();
}

class _DishCardState extends State<DishCard> {
  bool _isPressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _isPressed = true),
      onTapUp: (_) {
        setState(() => _isPressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.97 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: CupertinoColors.systemGrey.withValues(alpha: 0.25),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background image or placeholder
                Hero(
                  tag: 'dish-${widget.dish.id}',
                  child: widget.dish.hasImage
                      ? Image.network(
                          widget.dish.imageUrl,
                          fit: BoxFit.cover,
                          loadingBuilder: (context, child, progress) {
                            if (progress == null) return child;
                            return _buildPlaceholder(context);
                          },
                          errorBuilder: (_, __, ___) => _buildPlaceholder(context),
                        )
                      : _buildPlaceholder(context),
                ),

                // Gradient overlay
                const Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0x00000000),
                          Color(0x00000000),
                          Color(0xB3000000),
                        ],
                        stops: [0.0, 0.4, 1.0],
                      ),
                    ),
                  ),
                ),

                // Prep time pill (only if prepTime > 0)
                if (widget.dish.prepTime > 0)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0x40FFFFFF),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                CupertinoIcons.clock,
                                size: 13,
                                color: CupertinoColors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${widget.dish.prepTime} Min',
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

                // Bottom text
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.dish.name(widget.lang),
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: CupertinoColors.white,
                          letterSpacing: -0.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (widget.dish.hasCategory ||
                          widget.dish.isVegetarian) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            if (widget.dish.hasCategory)
                              _buildSmallTag(widget.dish.category),
                            if (widget.dish.isVegetarian) ...[
                              if (widget.dish.hasCategory)
                                const SizedBox(width: 6),
                              _buildSmallTag(
                                widget.dish.isVegan ? 'Vegan' : 'Vegetarisch',
                                color: const Color(0x5030D158),
                                textColor: const Color(0xFF30D158),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
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
          size: 40,
          color: CupertinoColors.systemGrey2.resolveFrom(context),
        ),
      ),
    );
  }

  Widget _buildSmallTag(
    String label, {
    Color color = const Color(0x40FFFFFF),
    Color textColor = CupertinoColors.white,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }
}
