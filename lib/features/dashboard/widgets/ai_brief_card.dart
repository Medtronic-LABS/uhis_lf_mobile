import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_brief.dart';

/// AI Daily Brief Card — the first and most prominent card on the dashboard.
///
/// Displays a summary of today's recommended work with an expandable
/// "Why?" section showing risk factors.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 2.
class AIBriefCard extends StatefulWidget {
  const AIBriefCard({
    super.key,
    required this.brief,
    this.onContinueWork,
  });

  final MissionBrief brief;
  final VoidCallback? onContinueWork;

  @override
  State<AIBriefCard> createState() => _AIBriefCardState();
}

class _AIBriefCardState extends State<AIBriefCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brief = widget.brief;

    // Determine accent color based on priority
    final accentColor = _priorityColor(brief.priorityLevel, scheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Compact header with visits count inline
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.12),
                  accentColor.withValues(alpha: 0.04),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  color: accentColor,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  'Today · ${DateFormat('d MMM').format(DateTime.now())}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: scheme.onSurface,
                      ),
                ),
                const SizedBox(width: 8),
                _PriorityBadge(priority: brief.priorityLevel),
                const Spacer(),
                // Compact visits stat
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.directions_walk, size: 14, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        '${brief.visitsRecommended}',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'visits',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: accentColor.withValues(alpha: 0.8),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Compact detail rows in a grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _CompactDetailRow(
                        icon: Icons.warning_amber_rounded,
                        iconColor: scheme.error,
                        label: MissionDashboardStrings.childDangerCases,
                        value: brief.childDangerCases.toString(),
                        isHighlight: brief.childDangerCases > 0,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactDetailRow(
                        icon: Icons.timelapse,
                        iconColor: const Color(0xFFF97316),
                        label: MissionDashboardStrings.slaBreachedReferrals,
                        value: brief.slaBreachedReferrals.toString(),
                        isHighlight: brief.slaBreachedReferrals > 0,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Expanded(
                      child: _CompactDetailRow(
                        icon: Icons.pregnant_woman,
                        iconColor: const Color(0xFFEC4899),
                        label: MissionDashboardStrings.ancFollowUps,
                        value: brief.ancFollowUps.toString(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _CompactDetailRow(
                        icon: Icons.medication,
                        iconColor: scheme.primary,
                        label: MissionDashboardStrings.highRiskDiabeticPatients,
                        value: brief.highRiskDiabeticPatients.toString(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Compact workload row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHigh.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.schedule, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            MissionDashboardStrings.workloadHours(brief.expectedWorkloadHours),
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: scheme.outlineVariant,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.directions_walk, size: 14, color: scheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            '${brief.estimatedDistanceKm.toStringAsFixed(1)} km',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onSurface,
                                ),
                          ),
                        ],
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: scheme.outlineVariant,
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.flag, size: 14, color: accentColor),
                          const SizedBox(width: 4),
                          Text(
                            brief.priorityLevel.label,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: accentColor,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                // Expandable risk factors
                if (brief.riskFactors.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  InkWell(
                    onTap: () => setState(() => _expanded = !_expanded),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            MissionDashboardStrings.whyQuestion,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: accentColor,
                                  fontWeight: FontWeight.w600,
                                ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            _expanded
                                ? Icons.keyboard_arrow_up
                                : Icons.keyboard_arrow_down,
                            color: accentColor,
                            size: 20,
                          ),
                        ],
                      ),
                    ),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: _RiskFactorsPanel(factors: brief.riskFactors),
                    crossFadeState: _expanded
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 200),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Color _priorityColor(DayPriorityLevel priority, ColorScheme scheme) {
    switch (priority) {
      case DayPriorityLevel.critical:
        return scheme.error;
      case DayPriorityLevel.high:
        return const Color(0xFFF97316); // orange-500
      case DayPriorityLevel.medium:
        return const Color(0xFFEAB308); // yellow-500
      case DayPriorityLevel.low:
        return scheme.primary;
    }
  }
}

class _PriorityBadge extends StatelessWidget {
  const _PriorityBadge({required this.priority});

  final DayPriorityLevel priority;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = _getColor(scheme);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 8, color: color),
          const SizedBox(width: 3),
          Text(
            priority.label.toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                  fontSize: 9,
                ),
          ),
        ],
      ),
    );
  }

  Color _getColor(ColorScheme scheme) {
    switch (priority) {
      case DayPriorityLevel.critical:
        return scheme.error;
      case DayPriorityLevel.high:
        return const Color(0xFFF97316);
      case DayPriorityLevel.medium:
        return const Color(0xFFEAB308);
      case DayPriorityLevel.low:
        return scheme.primary;
    }
  }
}

/// Compact detail row with icon for the AI brief card grid layout.
class _CompactDetailRow extends StatelessWidget {
  const _CompactDetailRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isHighlight
            ? scheme.errorContainer.withValues(alpha: 0.4)
            : scheme.surfaceContainerHigh.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: isHighlight ? scheme.error : iconColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isHighlight ? scheme.error : scheme.onSurface,
                ),
          ),
        ],
      ),
    );
  }
}

class _MainStat extends StatelessWidget {
  const _MainStat({
    required this.value,
    required this.label,
    required this.accentColor,
  });

  final String value;
  final String label;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: accentColor,
              ),
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.emoji,
    required this.label,
    required this.value,
    this.isHighlight = false,
  });

  final String emoji;
  final String label;
  final String value;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(emoji, style: const TextStyle(fontSize: 14)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: isHighlight
                ? scheme.errorContainer
                : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isHighlight ? scheme.error : scheme.onSurface,
                ),
          ),
        ),
      ],
    );
  }
}

class _WorkloadChip extends StatelessWidget {
  const _WorkloadChip({
    required this.icon,
    required this.label,
    required this.value,
    this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final chipColor = color ?? scheme.primary;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: scheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: chipColor,
              ),
        ),
      ],
    );
  }
}

class _RiskFactorsPanel extends StatelessWidget {
  const _RiskFactorsPanel({required this.factors});

  final List<String> factors;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            MissionDashboardStrings.riskFactorsIdentified,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: scheme.error,
                ),
          ),
          const SizedBox(height: 12),
          ...factors.map((factor) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(color: scheme.error)),
                    Expanded(
                      child: Text(
                        factor,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: scheme.onSurface,
                            ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
