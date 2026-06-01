import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/mission_brief.dart';

/// Compact summary strip showing AI brief + progress in a single row.
/// Designed to minimize vertical space while showing key metrics.
class CompactSummaryStrip extends StatelessWidget {
  const CompactSummaryStrip({
    super.key,
    required this.brief,
    required this.progress,
    this.onTap,
  });

  final MissionBrief brief;
  final MissionProgress progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hasCritical = brief.hasCriticalItems;
    final accentColor = hasCritical ? scheme.error : scheme.primary;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: hasCritical
              ? scheme.errorContainer.withValues(alpha: 0.4)
              : scheme.primaryContainer.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: accentColor.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // AI indicator
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.auto_awesome,
                size: 16,
                color: accentColor,
              ),
            ),
            const SizedBox(width: 10),

            // Main metrics
            Expanded(
              child: Row(
                children: [
                  // Visits recommended
                  _MetricChip(
                    value: brief.visitsRecommended.toString(),
                    label: 'visits',
                    icon: Icons.directions_walk,
                    color: accentColor,
                  ),
                  const SizedBox(width: 8),

                  // Critical alerts (if any)
                  if (brief.childDangerCases > 0 || brief.slaBreachedReferrals > 0)
                    _MetricChip(
                      value: (brief.childDangerCases + brief.slaBreachedReferrals)
                          .toString(),
                      label: 'urgent',
                      icon: Icons.warning_amber,
                      color: scheme.error,
                    ),
                  if (brief.childDangerCases > 0 || brief.slaBreachedReferrals > 0)
                    const SizedBox(width: 8),

                  // Workload estimate
                  if (brief.expectedWorkloadHours > 0)
                    _MetricChip(
                      value: brief.expectedWorkloadHours >= 1
                          ? '${brief.expectedWorkloadHours.toStringAsFixed(0)}h'
                          : '${(brief.expectedWorkloadHours * 60).toInt()}m',
                      label: 'work',
                      icon: Icons.schedule,
                      color: scheme.onSurfaceVariant,
                    ),
                ],
              ),
            ),

            // Progress indicator (compact)
            if (progress.totalVisits > 0) ...[
              const SizedBox(width: 8),
              _CompactProgressRing(
                progress: progress,
                size: 36,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
        const SizedBox(width: 2),
        Text(
          label,
          style: TextStyle(
            fontSize: 10,
            color: color.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
  }
}

class _CompactProgressRing extends StatelessWidget {
  const _CompactProgressRing({
    required this.progress,
    required this.size,
  });

  final MissionProgress progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final percent = progress.percentComplete / 100;
    final isComplete = progress.isComplete;
    final color = isComplete
        ? tokens.statusSuccess
        : (percent >= 0.5 ? scheme.primary : tokens.statusWarning);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CircularProgressIndicator(
            value: percent,
            strokeWidth: 3,
            backgroundColor: scheme.surfaceContainerHigh,
            valueColor: AlwaysStoppedAnimation(color),
          ),
          Text(
            '${progress.completedVisits}/${progress.totalVisits}',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Empty state when no AI brief is available.
class EmptySummaryStrip extends StatelessWidget {
  const EmptySummaryStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 18,
            color: scheme.primary.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'No visits scheduled today',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
