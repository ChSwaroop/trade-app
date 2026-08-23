import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../data/models/quote.dart';

/// Briefly tints its background when [triggerSequence] changes, green for an
/// uptick and red for a downtick, then fades back over 300ms.
///
/// The animation is entirely local state. A tick repaints this subtree only —
/// the row it sits in, and the list around it, are untouched. Rapid ticks
/// restart the fade rather than queueing, so the stress case reads as a
/// sustained glow instead of a strobe.
class FlashOnChange extends StatefulWidget {
  const FlashOnChange({
    required this.triggerSequence,
    required this.direction,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    super.key,
  });

  /// Changing this value fires the flash. The quote's per-symbol sequence is
  /// used rather than the price itself, so two consecutive ticks that land on
  /// the same price still register as separate prints.
  final int triggerSequence;

  final TickDirection direction;

  final EdgeInsets padding;

  final Widget child;

  @override
  State<FlashOnChange> createState() => _FlashOnChangeState();
}

class _FlashOnChangeState extends State<FlashOnChange>
    with SingleTickerProviderStateMixin {
  static const Duration _fadeDuration = Duration(milliseconds: 320);

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _fadeDuration,
  );

  Color _flashColor = Colors.transparent;

  @override
  void didUpdateWidget(FlashOnChange oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.triggerSequence != oldWidget.triggerSequence &&
        widget.direction != TickDirection.flat) {
      _flashColor = widget.direction == TickDirection.up
          ? AppColors.buyFlash
          : AppColors.sellFlash;
      _controller
        ..value = 1
        ..reverse();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary isolates the fade's repaints from the rest of the row.
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _controller,
        // The child is built once and reused across every animation frame —
        // only the DecoratedBox's colour is interpolated.
        child: Padding(padding: widget.padding, child: widget.child),
        builder: (BuildContext context, Widget? child) {
          return DecoratedBox(
            decoration: BoxDecoration(
              color: _flashColor.withValues(alpha: _flashColor.a * _controller.value),
              borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
            ),
            child: child,
          );
        },
      ),
    );
  }
}
