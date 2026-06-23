import 'package:flutter/material.dart';

import '../../app/theme.dart';

/// Urgency level for the badge.
enum UrgencyLevel {
  visitNow,
  today,
  thisWeek,
  routine,
  urgent,
}

/// A badge widget that displays urgency levels with corresponding colors.
/// Uses the [UrgencyTheme] extension from the app theme.
class UrgencyBadge extends StatelessWidget {
  const UrgencyBadge({
    super.key,
    required this.level,
    this.compact = false,
  });

  final UrgencyLevel level;
  final bool compact;

  String get _label {
    switch (level) {
      case UrgencyLevel.visitNow:
        return 'Visit now';
      case UrgencyLevel.today:
        return 'Today';
      case UrgencyLevel.thisWeek:
        return 'This week';
      case UrgencyLevel.routine:
        return 'Routine';
      case UrgencyLevel.urgent:
        return 'Urgent';
    }
  }

  IconData get _icon {
    switch (level) {
      case UrgencyLevel.visitNow:
        return Icons.directions_run;
      case UrgencyLevel.today:
        return Icons.today;
      case UrgencyLevel.thisWeek:
        return Icons.date_range;
      case UrgencyLevel.routine:
        return Icons.schedule;
      case UrgencyLevel.urgent:
        return Icons.priority_high;
    }
  }

  (Color, Color) _colors(UrgencyTheme urgency) {
    switch (level) {
      case UrgencyLevel.visitNow:
        return (urgency.visitNow, urgency.visitNowContainer);
      case UrgencyLevel.today:
        return (urgency.today, urgency.todayContainer);
      case UrgencyLevel.thisWeek:
        return (urgency.thisWeek, urgency.thisWeekContainer);
      case UrgencyLevel.routine:
        return (urgency.routine, urgency.routineContainer);
      case UrgencyLevel.urgent:
        return (urgency.urgent, urgency.urgentContainer);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final urgency = theme.extension<UrgencyTheme>()!;
    final (foreground, background) = _colors(urgency);

    if (compact) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          _label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: foreground.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _icon,
            size: 14,
            color: foreground,
          ),
          const SizedBox(width: 5),
          Text(
            _label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper function to convert a risk score to an urgency level.
UrgencyLevel urgencyLevelFromScore(int score) {
  if (score >= 90) return UrgencyLevel.visitNow;
  if (score >= 70) return UrgencyLevel.urgent;
  if (score >= 50) return UrgencyLevel.today;
  if (score >= 30) return UrgencyLevel.thisWeek;
  return UrgencyLevel.routine;
}
