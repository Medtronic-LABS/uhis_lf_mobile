import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../cce_alert.dart';

/// Horizontal 4-node care-journey strip: SK Visit → Referred → Facility →
/// Treatment. Each node is a coloured dot with a label + sublabel; connector
/// lines tint green up to the last completed step and red at a missed step.
class CceJourneyStrip extends StatelessWidget {
  const CceJourneyStrip({super.key, required this.steps});

  final List<CceJourneyStep> steps;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < steps.length; i++) {
      children.add(Expanded(child: _node(steps[i])));
      if (i < steps.length - 1) {
        children.add(_connector(steps[i], steps[i + 1]));
      }
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _node(CceJourneyStep step) {
    final (bg, icon, iconColor) = _visuals(step.state);
    return Column(
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
          child: Icon(icon, size: 15, color: iconColor),
        ),
        const SizedBox(height: 4),
        Text(
          step.label,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700),
        ),
        Text(
          step.sublabel,
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 9, color: AppColors.textMuted),
        ),
      ],
    );
  }

  /// Connector colour reflects the transition into the next node: red when the
  /// next step is missed, green when this step is done, grey otherwise.
  Widget _connector(CceJourneyStep from, CceJourneyStep to) {
    Color color;
    if (to.state == CceStepState.missed) {
      color = AppColors.statusCritical;
    } else if (from.state == CceStepState.done) {
      color = AppColors.statusSuccess;
    } else {
      color = AppColors.border;
    }
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(width: 18, height: 2.5, color: color),
    );
  }

  (Color, IconData, Color) _visuals(CceStepState state) {
    switch (state) {
      case CceStepState.done:
        return (AppColors.statusSuccess, Icons.check, Colors.white);
      case CceStepState.missed:
        return (AppColors.statusCritical, Icons.close, Colors.white);
      case CceStepState.pending:
        return (AppColors.border, Icons.more_horiz, AppColors.textMuted);
    }
  }
}
