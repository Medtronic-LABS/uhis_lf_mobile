import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_queue_item.dart';

/// Follow-Ups Due Widget — post-discharge follow-up tracking.
///
/// Prevents patients from disappearing after treatment by showing
/// upcoming and overdue follow-ups.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 7.
class FollowUpsDueWidget extends StatelessWidget {
  const FollowUpsDueWidget({
    super.key,
    required this.followUps,
    this.onScheduleVisit,
    this.onViewAll,
  });

  final List<FollowUpDue> followUps;
  final void Function(FollowUpDue)? onScheduleVisit;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (followUps.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: scheme.secondary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.event_repeat,
                    color: scheme.secondary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MissionDashboardStrings.followUpsDue,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Text(
                        '${followUps.length} pending',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                ),
                if (followUps.length > 3)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: Text(MissionDashboardStrings.viewAll, style: const TextStyle(fontSize: 12)),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Follow-up cards
            ...followUps.take(3).map((followUp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _FollowUpCard(
                    followUp: followUp,
                    onSchedule: onScheduleVisit != null
                        ? () => onScheduleVisit!(followUp)
                        : null,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _FollowUpCard extends StatelessWidget {
  const _FollowUpCard({
    required this.followUp,
    this.onSchedule,
  });

  final FollowUpDue followUp;
  final VoidCallback? onSchedule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final isOverdue = followUp.isOverdue(now);
    final daysUntil = followUp.daysUntilDue(now);

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isOverdue
            ? scheme.errorContainer.withValues(alpha: 0.2)
            : scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: isOverdue
            ? Border.all(color: scheme.error.withValues(alpha: 0.3))
            : null,
      ),
      child: Row(
        children: [
          // Patient info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  followUp.patientName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    // Discharged date
                    if (followUp.dischargedAt != null) ...[
                      _InfoChip(
                        icon: Icons.logout,
                        label: MissionDashboardStrings.discharged,
                        value: _formatDate(followUp.dischargedAt!),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // Due date
                    _InfoChip(
                      icon: Icons.event,
                      label: MissionDashboardStrings.followUpDue,
                      value: _formatDueDate(daysUntil),
                      isHighlight: isOverdue,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Schedule button
          FilledButton.tonal(
            onPressed: onSchedule,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              visualDensity: VisualDensity.compact,
              textStyle: const TextStyle(fontSize: 11),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.event, size: 14),
                const SizedBox(width: 4),
                Text(MissionDashboardStrings.scheduleVisit),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${date.day} ${months[date.month - 1]}';
  }

  String _formatDueDate(int daysUntil) {
    if (daysUntil < -1) return '${-daysUntil} days ago';
    if (daysUntil == -1) return 'Yesterday';
    if (daysUntil == 0) return MissionDashboardStrings.today;
    if (daysUntil == 1) return MissionDashboardStrings.tomorrow;
    return MissionDashboardStrings.daysAway(daysUntil);
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isHighlight ? scheme.error : scheme.onSurfaceVariant;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          value,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: color,
                fontWeight: isHighlight ? FontWeight.bold : null,
              ),
        ),
      ],
    );
  }
}
