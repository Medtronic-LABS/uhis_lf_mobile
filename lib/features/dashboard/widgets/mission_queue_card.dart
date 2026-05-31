import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_queue_item.dart';
import '../../../core/models/programme.dart';

/// Mission Queue Card — prioritized action card for the mission queue.
///
/// Shows patient info, priority badge, programme badge, reason,
/// AI explanation, and available actions.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 5.
class MissionQueueCard extends StatelessWidget {
  const MissionQueueCard({
    super.key,
    required this.item,
    required this.rank,
    this.onAction,
    this.onTap,
  });

  final MissionQueueItem item;
  final int rank;
  final void Function(MissionQueueItem, MissionAction)? onAction;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final priorityColor = _priorityColor(item.priority, scheme);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: item.isCritical
            ? BorderSide(color: priorityColor.withValues(alpha: 0.5), width: 1.5)
            : BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: Priority rank + badges
              Row(
                children: [
                  // Priority rank badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: priorityColor.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.circle,
                          size: 8,
                          color: priorityColor,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          MissionDashboardStrings.priorityRank(rank),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: priorityColor,
                                    fontSize: 10,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Programme badge
                  if (item.programmes.isNotEmpty)
                    _ProgrammeBadge(programme: item.programmes.first),
                  if (item.type == MissionItemType.referral)
                    _TypeBadge(
                      label: MissionDashboardStrings.badgeReferral,
                      color: scheme.tertiary,
                    ),
                  const Spacer(),
                  // Overdue indicator
                  if (item.daysOverdue != null && item.daysOverdue! > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.errorContainer,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        MissionDashboardStrings.daysOverdue(item.daysOverdue!),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.error,
                            ),
                      ),
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Patient info row
              Row(
                children: [
                  // Avatar with programme icon
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: priorityColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Center(
                      child: Icon(
                        _programmeIcon(item.programmes),
                        size: 22,
                        color: priorityColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Name and details
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.patientName,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            if (item.age != null) ...[
                              Text(
                                item.ageDisplay,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                              ),
                              if (item.village != null) _Dot(),
                            ],
                            if (item.village != null)
                              Expanded(
                                child: Text(
                                  item.village!,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 10),

              // Reason chip
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      _reasonIcon(item.reason),
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        item.reason,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                      ),
                    ),
                  ],
                ),
              ),

              // Actions row
              if (item.availableActions.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: item.availableActions
                      .take(3)
                      .map((action) => _ActionButton(
                            action: action,
                            onPressed: onAction != null
                                ? () => onAction!(item, action)
                                : null,
                          ))
                      .toList(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Color _priorityColor(MissionPriority priority, ColorScheme scheme) {
    switch (priority) {
      case MissionPriority.critical:
        return scheme.error;
      case MissionPriority.high:
        return const Color(0xFFF97316); // orange-500
      case MissionPriority.medium:
        return const Color(0xFFEAB308); // yellow-500
      case MissionPriority.low:
        return const Color(0xFF22C55E); // green-500
    }
  }

  IconData _reasonIcon(String reason) {
    final lower = reason.toLowerCase();
    if (lower.contains('referral')) return Icons.local_hospital;
    if (lower.contains('anc') || lower.contains('pregnan')) return Icons.pregnant_woman;
    if (lower.contains('child') || lower.contains('imci')) return Icons.child_care;
    if (lower.contains('diabetes') || lower.contains('ncd')) return Icons.medical_services;
    if (lower.contains('follow')) return Icons.event_repeat;
    if (lower.contains('missed')) return Icons.event_busy;
    return Icons.assignment;
  }

  IconData _programmeIcon(Set<Programme> programmes) {
    if (programmes.contains(Programme.imci)) return Icons.child_care;
    if (programmes.contains(Programme.anc)) return Icons.pregnant_woman;
    if (programmes.contains(Programme.ncd)) return Icons.medication;
    if (programmes.contains(Programme.tb)) return Icons.air;
    return Icons.person;
  }
}

class _ProgrammeBadge extends StatelessWidget {
  const _ProgrammeBadge({required this.programme});

  final Programme programme;

  @override
  Widget build(BuildContext context) {
    final (color, label) = _programmeInfo(programme);
    
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 10,
            ),
      ),
    );
  }

  (Color, String) _programmeInfo(Programme p) {
    switch (p) {
      case Programme.imci:
        return (const Color(0xFFDC2626), MissionDashboardStrings.badgeImci);
      case Programme.anc:
        return (const Color(0xFFEC4899), MissionDashboardStrings.badgeAnc);
      case Programme.ncd:
        return (const Color(0xFFD97706), MissionDashboardStrings.badgeNcd);
      case Programme.tb:
        return (const Color(0xFF16A34A), MissionDashboardStrings.badgeTb);
    }
  }
}

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
              fontSize: 10,
            ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.action,
    this.onPressed,
  });

  final MissionAction action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final (icon, label) = _actionInfo(action);
    final scheme = Theme.of(context).colorScheme;

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: scheme.outline.withValues(alpha: 0.5)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(6),
        ),
      ),
    );
  }

  (IconData, String) _actionInfo(MissionAction action) {
    switch (action) {
      case MissionAction.callFamily:
        return (Icons.phone, MissionDashboardStrings.callFamily);
      case MissionAction.locate:
        return (Icons.location_on, MissionDashboardStrings.locate);
      case MissionAction.openCase:
        return (Icons.folder_open, MissionDashboardStrings.openCase);
      case MissionAction.callFacility:
        return (Icons.local_hospital, MissionDashboardStrings.callFacility);
      case MissionAction.openReferral:
        return (Icons.assignment, MissionDashboardStrings.openReferral);
      case MissionAction.scheduleVisit:
        return (Icons.event, MissionDashboardStrings.scheduleVisit);
      case MissionAction.visitHousehold:
        return (Icons.home, MissionDashboardStrings.visitHousehold);
      case MissionAction.updateStatus:
        return (Icons.edit, ReferralStrings.actionUpdateStatus);
      case MissionAction.escalate:
        return (Icons.arrow_upward, ReferralStrings.actionEscalate);
    }
  }
}
