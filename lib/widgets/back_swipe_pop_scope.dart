import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

/// Adds a reusable edge-swipe-back gesture to any page.
///
/// The gesture only activates when a drag starts near the left edge and the
/// movement is predominantly horizontal, so vertical scrolling keeps working.
class BackSwipePopScope extends StatefulWidget {
  final Widget child;
  final bool Function()? canPop;
  final double edgeWidthFactor;
  final double dismissThresholdFactor;
  final double minFlingVelocity;
  final double minEdgeWidth;
  final double directionDominanceFactor;
  final double directionLockSlop;
  final Duration snapBackDuration;

  const BackSwipePopScope({
    super.key,
    required this.child,
    this.canPop,
    this.edgeWidthFactor = 0.08,
    this.dismissThresholdFactor = 0.20,
    this.minFlingVelocity = 700,
    this.minEdgeWidth = 24,
    this.directionDominanceFactor = 1.2,
    this.directionLockSlop = kTouchSlop,
    this.snapBackDuration = const Duration(milliseconds: 180),
  });

  @override
  State<BackSwipePopScope> createState() => _BackSwipePopScopeState();
}

class _BackSwipePopScopeState extends State<BackSwipePopScope> {
  bool _tracking = false;
  bool _directionLocked = false;
  bool _isHorizontalIntent = false;
  Offset? _startGlobal;
  double _dragDistance = 0;
  bool _isDragging = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _onDragStart,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: _animateBack,
      child: AnimatedContainer(
        duration: _isDragging ? Duration.zero : widget.snapBackDuration,
        curve: Curves.easeOutCubic,
        transform: Matrix4.translationValues(_dragDistance, 0, 0),
        child: widget.child,
      ),
    );
  }

  void _onDragStart(DragStartDetails details) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final edgeWidth = math.max(
      widget.minEdgeWidth,
      screenWidth * widget.edgeWidthFactor,
    );

    _startGlobal = details.globalPosition;
    _dragDistance = 0;
    _directionLocked = false;
    _isHorizontalIntent = false;
    _isDragging = false;
    _tracking = details.globalPosition.dx <= edgeWidth;
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_tracking) return;

    final start = _startGlobal;
    if (start == null) return;

    final totalDx = details.globalPosition.dx - start.dx;
    final totalDy = (details.globalPosition.dy - start.dy).abs();

    if (!_directionLocked &&
        (totalDx.abs() > widget.directionLockSlop ||
            totalDy > widget.directionLockSlop)) {
      _isHorizontalIntent =
          totalDx.abs() > totalDy * widget.directionDominanceFactor;
      _directionLocked = true;
    }

    if (_directionLocked && (!_isHorizontalIntent || totalDx <= 0)) {
      _animateBack();
      return;
    }

    if (totalDx > 0) {
      final clampedDx = totalDx.clamp(0.0, MediaQuery.sizeOf(context).width);
      if (mounted) {
        setState(() {
          _dragDistance = clampedDx;
          _isDragging = true;
        });
      }
    }
  }

  Future<void> _onDragEnd(DragEndDetails details) async {
    if (!_tracking) {
      _animateBack();
      return;
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final shouldPopByDistance =
        _dragDistance >= screenWidth * widget.dismissThresholdFactor;
    final velocity = details.primaryVelocity ?? 0;
    final shouldPopByVelocity = velocity > widget.minFlingVelocity;

    final canPop = widget.canPop?.call() ?? Navigator.of(context).canPop();

    if (canPop && (shouldPopByDistance || shouldPopByVelocity)) {
      _resetState();
      await Navigator.of(context).maybePop();
      return;
    }

    _animateBack();
  }

  void _animateBack() {
    if (!mounted) return;
    setState(() {
      _resetState();
    });
  }

  void _resetState() {
    _tracking = false;
    _directionLocked = false;
    _isHorizontalIntent = false;
    _startGlobal = null;
    _isDragging = false;
    _dragDistance = 0;
  }
}

