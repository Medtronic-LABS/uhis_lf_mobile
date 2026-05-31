import 'package:flutter/material.dart';

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
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: accentColor.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header with gradient
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              gradient: LinearGradient(
                colors: [
                  accentColor.withValues(alpha: 0.15),
                  accentColor.withValues(alpha: 0.05),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        Icons.auto_awesome,
                        color: accentColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            MissionDashboardStrings.aiBriefTitle,
                            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: scheme.onSurface,
                                ),
                          ),
                          const SizedBox(height: 2),
                          _PriorityBadge(priority: brief.priorityLevel),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Main stat - Visits Recommended
                _MainStat(
                  value: brief.visitsRecommended.toString(),
                  label: MissionDashboardStrings.visitsRecommended,
                  accentColor: accentColor,
                ),
              ],
            ),
          ),

          // Detail rows
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                _DetailRow(
                  emoji: '🚨',
                  label: MissionDashboardStrings.childDangerCases,
                  value: brief.childDangerCases.toString(),
                  isHighlight: brief.childDangerCases > 0,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  emoji: '🔴',
                  label: MissionDashboardStrings.slaBreachedReferrals,
                  value: brief.slaBreachedReferrals.toString(),
                  isHighlight: brief.slaBreachedReferrals > 0,
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  emoji: '🤰',
                  label: MissionDashboardStrings.ancFollowUps,
                  value: brief.ancFollowUps.toString(),
                ),
                const SizedBox(height: 8),
                _DetailRow(
                  emoji: '💊',
                  label: MissionDashboardStrings.highRiskDiabeticPatients,
                  value: brief.highRiskDiabeticPatients.toString(),
                ),
                const Divider(height: 24),
                // Workload estimate
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _WorkloadChip(
                      icon: Icons.schedule,
                      label: MissionDashboardStrings.expectedWorkload,
                      value: MissionDashboardStrings.workloadHours(
                        brief.expectedWorkloadHours,
                      ),
                    ),
                    _WorkloadChip(
                      icon: Icons.flag,
                      label: MissionDashboardStrings.priorityLevel,
                      value: brief.priorityLevel.label,
                      color: accentColor,
                    ),
                  ],
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
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${_getEmoji()} ${priority.label.toUpperCase()}',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 10,
            ),
      ),
    );
  }

  String _getEmoji() {
    switch (priority) {
      case DayPriorityLevel.critical:
        return '🔴';
      case DayPriorityLevel.high:
        return '🟠';
      case DayPriorityLevel.medium:
        return '🟡';
      case DayPriorityLevel.low:
        return '🟢';
    }
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
