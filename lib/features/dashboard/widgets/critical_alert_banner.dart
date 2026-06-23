import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_queue_item.dart';
import '../../../core/models/programme.dart';

/// Critical Alert Banner — sticky banner for urgent cases.
///
/// Shown only when critical alerts exist. Stays at the top of the
/// dashboard until the user takes action.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 4.
class CriticalAlertBanner extends StatelessWidget {
  const CriticalAlertBanner({
    super.key,
    required this.alerts,
    this.onOpenCase,
    this.onDismiss,
  });

  final List<MissionQueueItem> alerts;
  final void Function(MissionQueueItem)? onOpenCase;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    if (alerts.isEmpty) return const SizedBox.shrink();

    final scheme = Theme.of(context).colorScheme;
    final topAlert = alerts.first;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        gradient: LinearGradient(
          colors: [
            scheme.error,
            scheme.error.withValues(alpha: 0.85),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: scheme.error.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpenCase != null ? () => onOpenCase!(topAlert) : null,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.warning_rounded,
                        color: Colors.white,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _alertTitle(topAlert),
                            style:
                                Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                          ),
                          if (alerts.length > 1) ...[
                            const SizedBox(height: 2),
                            Text(
                              '+${alerts.length - 1} more alert${alerts.length > 2 ? 's' : ''}',
                              style:
                                  Theme.of(context).textTheme.bodySmall?.copyWith(
                                        color: Colors.white.withValues(alpha: 0.8),
                                      ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (onDismiss != null)
                      IconButton(
                        onPressed: onDismiss,
                        icon: Icon(
                          Icons.close,
                          color: Colors.white.withValues(alpha: 0.8),
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),

                const SizedBox(height: 10),

                // Patient info
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      // Avatar with programme icon
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Icon(
                            _programmeIcon(topAlert.programmes),
                            size: 20,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              topAlert.patientName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                if (topAlert.age != null) ...[
                                  Text(
                                    topAlert.ageDisplay,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.9),
                                        ),
                                  ),
                                  _Dot(),
                                ],
                                Expanded(
                                  child: Text(
                                    topAlert.reason,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                          color: Colors.white.withValues(alpha: 0.9),
                                        ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (topAlert.daysOverdue != null && topAlert.daysOverdue! > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '+${topAlert.daysOverdue}d',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: scheme.error,
                                    ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Action button
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            onOpenCase != null ? () => onOpenCase!(topAlert) : null,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(MissionDashboardStrings.openCase),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: scheme.error,
                          minimumSize: const Size.fromHeight(36),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  IconData _programmeIcon(Set<Programme> programmes) {
    if (programmes.contains(Programme.imci)) return Icons.child_care;
    if (programmes.contains(Programme.anc)) return Icons.pregnant_woman;
    if (programmes.contains(Programme.ncd)) return Icons.medication;
    if (programmes.contains(Programme.tb)) return Icons.air;
    return Icons.person;
  }

  String _alertTitle(MissionQueueItem item) {
    if (item.type == MissionItemType.referral) {
      if (item.programmes.isNotEmpty && item.age != null && item.age! < 5) {
        return MissionDashboardStrings.criticalAlert;
      }
      return MissionDashboardStrings.criticalAlert;
    }
    if (item.programmes.any((p) => p.name == 'anc')) {
      return MissionDashboardStrings.emergencyAncAlert;
    }
    return MissionDashboardStrings.criticalAlert;
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
