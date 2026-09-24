import 'package:flutter/material.dart';

import 'pad_breakpoints.dart';

/// Vertical drag handle between left and right panes (≈14dp hit area).
class DragDivider extends StatelessWidget {
  const DragDivider({
    super.key,
    required this.onDrag,
    this.onDragEnd,
  });

  final ValueChanged<double> onDrag;
  final VoidCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    final outline = Theme.of(context).colorScheme.outline;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragUpdate: (d) => onDrag(d.delta.dx),
        onHorizontalDragEnd: (_) => onDragEnd?.call(),
        child: SizedBox(
          width: 14,
          child: Center(
            child: Container(
              width: 3,
              height: 56,
              decoration: BoxDecoration(
                color: outline,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Clamps left pane width given total width (logical px).
double clampLeftWidth(double left, double totalWidth) {
  final min = PadBreakpoints.leftMin;
  final max = (totalWidth * PadBreakpoints.leftMaxFraction)
      .clamp(min + 40, totalWidth - 120);
  return left.clamp(min, max);
}
