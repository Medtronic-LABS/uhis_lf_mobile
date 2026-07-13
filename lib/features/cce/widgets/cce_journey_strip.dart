import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../cce_alert.dart';

/// Thin horizontal progress bar + 3-label status row for the CCE card.
///
/// Renders steps[1..3] (SK Visit at index 0 is always done and not shown).
/// The bar fills to the furthest completed or missed node; the accent colour
/// is derived from the worst step state across the visible steps.
class CceJourneyStrip extends StatelessWidget {
  const CceJourneyStrip({super.key, required this.steps});

  final List<CceJourneyStep> steps;

  @override
  Widget build(BuildContext context) {
    final visible = steps.length > 1 ? steps.sublist(1) : steps;
    if (visible.isEmpty) return const SizedBox.shrink();

    final fill = _fillFraction(visible);
    final accent = _accentFrom(visible);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _progressBar(fill, accent),
        const SizedBox(height: 6),
        _labels(visible),
      ],
    );
  }

  // ── Progress bar ─────────────────────────────────────────────────────────

  Widget _progressBar(double fill, Color accent) {
    return LayoutBuilder(
      builder: (_, constraints) {
        const trackHeight = 3.0;
        const dotSize = 10.0;
        final totalWidth = constraints.maxWidth;
        final fillWidth = totalWidth * fill;

        return SizedBox(
          height: dotSize,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: AlignmentDirectional.centerStart,
            children: [
              // Track
              Positioned(
                top: (dotSize - trackHeight) / 2,
                left: 0,
                right: 0,
                child: Container(
                  height: trackHeight,
                  decoration: BoxDecoration(
                    color: AppColors.border,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
              ),
              // Fill
              if (fill > 0)
                Positioned(
                  top: (dotSize - trackHeight) / 2,
                  left: 0,
                  child: Container(
                    height: trackHeight,
                    width: fillWidth,
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              // Dot at fill endpoint — only when not at 0% or 100%
              if (fill > 0 && fill < 1)
                Positioned(
                  left: fillWidth - dotSize / 2,
                  child: Container(
                    width: dotSize,
                    height: dotSize,
                    decoration: BoxDecoration(
                      color: accent,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // ── Labels ───────────────────────────────────────────────────────────────

  Widget _labels(List<CceJourneyStep> visible) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: visible.map(_stepLabel).toList(),
    );
  }

  Widget _stepLabel(CceJourneyStep step) {
    final (icon, color) = _iconFor(step.state);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          Icon(icon, size: 12, color: color)
        else
          Text(
            '···',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        const SizedBox(width: 3),
        Text(
          step.label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  static (IconData?, Color) _iconFor(CceStepState state) {
    switch (state) {
      case CceStepState.done:
        return (Icons.check_rounded, AppColors.statusSuccess);
      case CceStepState.missed:
        return (Icons.close_rounded, AppColors.statusCritical);
      case CceStepState.pending:
        return (null, AppColors.textMuted);
    }
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Fill fraction: advances to each done step; advances to a missed step
  /// (filling up to the block point) then stops.
  static double _fillFraction(List<CceJourneyStep> steps) {
    if (steps.isEmpty) return 0;
    int pos = 0;
    for (int i = 0; i < steps.length; i++) {
      if (steps[i].state == CceStepState.done) {
        pos = i + 1;
      } else if (steps[i].state == CceStepState.missed) {
        pos = i + 1; // fill to the missed node
        break;
      } else {
        break;
      }
    }
    return pos / steps.length;
  }

  static Color _accentFrom(List<CceJourneyStep> steps) {
    if (steps.any((s) => s.state == CceStepState.missed)) {
      return AppColors.statusCritical;
    }
    if (steps.every((s) => s.state == CceStepState.done)) {
      return AppColors.statusSuccess;
    }
    return AppColors.statusWarning;
  }
}
