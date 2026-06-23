import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_queue_item.dart';

/// Referral Operations Widget — summary of referral status.
///
/// Shows active/breached/awaiting/completed counts and the top
/// breached referral for quick action.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 6.
class ReferralOperationsWidget extends StatelessWidget {
  const ReferralOperationsWidget({
    super.key,
    required this.summary,
    this.onOpenReferrals,
    this.onOpenReferral,
    this.onCallPatient,
  });

  final ReferralSummary summary;
  final VoidCallback? onOpenReferrals;
  final void Function(MissionQueueItem)? onOpenReferral;
  final void Function(MissionQueueItem)? onCallPatient;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: summary.hasBreaches
              ? scheme.error.withValues(alpha: 0.3)
              : scheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: onOpenReferrals,
        borderRadius: BorderRadius.circular(12),
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
                      color: scheme.tertiary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      Icons.local_hospital,
                      color: scheme.tertiary,
                      size: 16,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    MissionDashboardStrings.referralStatus,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Icon(
                    Icons.chevron_right,
                    color: scheme.onSurfaceVariant,
                    size: 20,
                  ),
                ],
              ),

              const SizedBox(height: 12),

              // Status counts row
              Row(
                children: [
                  _StatusCount(
                    count: summary.active,
                    label: MissionDashboardStrings.active,
                    color: scheme.primary,
                  ),
                  _StatusCount(
                    count: summary.breached,
                    label: MissionDashboardStrings.breached,
                    color: scheme.error,
                    isHighlight: summary.breached > 0,
                  ),
                  _StatusCount(
                    count: summary.awaitingReview,
                    label: MissionDashboardStrings.awaitingReview,
                    color: tokens.statusWarning,
                  ),
                  _StatusCount(
                    count: summary.completed,
                    label: MissionDashboardStrings.completed,
                    color: tokens.statusSuccess,
                  ),
                ],
              ),

              // Top breached referral card
              if (summary.topBreachedReferral != null) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 12),
                _TopBreachCard(
                  item: summary.topBreachedReferral!,
                  onOpen: onOpenReferral != null
                      ? () => onOpenReferral!(summary.topBreachedReferral!)
                      : null,
                  onCall: onCallPatient != null
                      ? () => onCallPatient!(summary.topBreachedReferral!)
                      : null,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusCount extends StatelessWidget {
  const _StatusCount({
    required this.count,
    required this.label,
    required this.color,
    this.isHighlight = false,
  });

  final int count;
  final String label;
  final Color color;
  final bool isHighlight;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: isHighlight
              ? color.withValues(alpha: 0.1)
              : scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(8),
          border: isHighlight
              ? Border.all(color: color.withValues(alpha: 0.3))
              : null,
        ),
        child: Column(
          children: [
            Text(
              count.toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isHighlight ? color : scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: isHighlight ? color : scheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBreachCard extends StatelessWidget {
  const _TopBreachCard({
    required this.item,
    this.onOpen,
    this.onCall,
  });

  final MissionQueueItem item;
  final VoidCallback? onOpen;
  final VoidCallback? onCall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          // Avatar with initials
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: scheme.error.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                _getInitials(item.patientName),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.error,
                    ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          // Name and status
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.patientName,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.error,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        '🔴 SLA BREACHED',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 10,
                            ),
                      ),
                    ),
                    if (item.daysOverdue != null && item.daysOverdue! > 0) ...[
                      const SizedBox(width: 6),
                      Text(
                        '+${item.daysOverdue}d',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              color: scheme.error,
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          // Action buttons
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: onOpen,
                icon: const Icon(Icons.open_in_new, size: 20),
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.all(4),
                constraints: const BoxConstraints(),
                tooltip: MissionDashboardStrings.openReferral,
              ),
              if (item.hasPhone)
                IconButton(
                  onPressed: onCall,
                  icon: const Icon(Icons.phone, size: 20),
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.all(4),
                  constraints: const BoxConstraints(),
                  tooltip: MissionDashboardStrings.callFamily,
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }
}
