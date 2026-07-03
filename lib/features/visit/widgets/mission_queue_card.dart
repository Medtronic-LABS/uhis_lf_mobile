import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/dashboard_tier.dart';
import '../../../core/models/mission_queue_item.dart';
import '../../../core/models/programme.dart';

/// Shared patient card widget for mission queue items.
/// Used by both Dashboard (home) and Tasks screens.
class MissionQueueCard extends StatelessWidget {
  const MissionQueueCard({
    super.key,
    required this.item,
    this.isCompleted = false,
    this.onTap,
    this.onAction,
    this.showActionButton = true,
    this.compact = false,
  });

  final MissionQueueItem item;
  final bool isCompleted;
  final VoidCallback? onTap;
  final VoidCallback? onAction;
  final bool showActionButton;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final borderColor = isCompleted
        ? tokens.statusSuccess
        : _borderColorForTier(item.tier, tokens);
    final avatarColor = _avatarColorForProgramme(item, tokens);
    final (dotLabel, dotColor) = isCompleted
        ? ('Done', tokens.statusSuccess)
        : _statusDotStyle(item.tier, tokens);
    final hasBorder = borderColor != const Color(0xFFE5E7EB);

    return Opacity(
      opacity: isCompleted ? 0.6 : 1.0,
      child: Padding(
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Semantics(
          label: 'View patient ${item.patientName}',
          button: true,
          child: Material(
            color: tokens.cardSurface,
            borderRadius: BorderRadius.circular(compact ? LeapfrogColors.radiusLg : 12),
            child: InkWell(
              key: const Key('visit_queue_card_tap'),
              onTap: isCompleted
                  ? () => ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            MissionDashboardStrings.completedVisitToast(
                                item.patientName),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      )
                  : onTap,
              borderRadius: BorderRadius.circular(compact ? LeapfrogColors.radiusLg : 12),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(compact ? LeapfrogColors.radiusLg : 12),
                  border: hasBorder
                      ? Border(left: BorderSide(color: borderColor, width: 4))
                      : null,
                ),
                padding: EdgeInsets.fromLTRB(hasBorder ? 14 : 16, 12, 12, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Avatar ──────────────────────────────────────────
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: isCompleted
                          ? tokens.statusSuccess.withValues(alpha: 0.18)
                          : avatarColor.withValues(alpha: 0.15),
                      child: isCompleted
                          ? Icon(Icons.check, color: tokens.statusSuccess, size: 22)
                          : Text(
                              _initials(item.patientName),
                              style: TextStyle(
                                color: avatarColor,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                    ),
                    const SizedBox(width: 12),

                    // ── Content ──────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Name + reason badge inline
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Flexible(
                                child: Text(
                                  item.patientName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    color: isCompleted
                                        ? tokens.textMuted
                                        : tokens.textPrimary,
                                    decoration: isCompleted
                                        ? TextDecoration.lineThrough
                                        : null,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 6),
                              if (isCompleted)
                                _VisitedBadge(tokens: tokens)
                              else
                                MissionReasonBadge(item: item),
                            ],
                          ),
                          const SizedBox(height: 5),
                          // Subtitle: age · house · village · programme emoji
                          Text(
                            _subtitle(item),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: tokens.textMuted,
                              height: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ── Status dot + label ───────────────────────────────
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _StatusDot(label: dotLabel, color: dotColor),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _subtitle(MissionQueueItem item) {
    final parts = <String>[];
    if (item.age != null) parts.add(WorklistStrings.ageFmt(item.age!));
    final house = item.householdDisplay;
    if (house.isNotEmpty) parts.add(house);
    if (item.village != null && item.village!.isNotEmpty) {
      parts.add(item.village!);
    }
    final diagnosis = item.diagnosisLabel;
    if (diagnosis != null && diagnosis.isNotEmpty) {
      parts.add('${item.programmeEmoji} $diagnosis');
    } else if (item.programmes.isNotEmpty &&
        !item.programmes.every((p) => p == Programme.unknown)) {
      parts.add(item.programmeEmoji);
    }
    if (parts.isEmpty) return item.reason;
    return parts.join(' · ');
  }

  /// Border colour — left accent shown only for urgent tiers.
  ///
  /// Overdue → amber. Critical + danger/CCE driver → red. All others →
  /// neutral grey (visually absent) so routine cards stay calm.
  Color _borderColorForTier(DashboardTier tier, LeapfrogColors tokens) {
    if (tier == DashboardTier.overdue) return AppColors.statusWarning;
    if (tier == DashboardTier.critical) {
      final cceOrDanger = item.drivers.any((d) =>
          d == 'sla-breached' ||
          d == 'danger-sign' ||
          d == 'stroke-sign' ||
          d == 'eclampsia');
      return cceOrDanger ? tokens.statusCritical : const Color(0xFFE5E7EB);
    }
    return const Color(0xFFE5E7EB);
  }

  /// Programme-coded avatar colour.
  static Color _avatarColorForProgramme(
      MissionQueueItem item, LeapfrogColors tokens) {
    if (item.programmes.contains(Programme.anc) ||
        item.programmes.contains(Programme.pnc)) {
      return tokens.brandPink;
    }
    if (item.programmes.contains(Programme.ncd)) {
      return AppColors.statusWarning;
    }
    if (item.programmes.contains(Programme.imci) ||
        item.programmes.contains(Programme.epi)) {
      return AppColors.statusInfo;
    }
    if (item.programmes.contains(Programme.tb)) {
      return AppColors.aiPurple;
    }
    return tokens.textMuted;
  }

  /// Status dot style: (label, dotColor) keyed by tier.
  (String, Color) _statusDotStyle(DashboardTier tier, LeapfrogColors tokens) {
    switch (tier) {
      case DashboardTier.critical:
        return (MissionDashboardStrings.statusPillForTier(tier), tokens.statusCritical);
      case DashboardTier.overdue:
        return (MissionDashboardStrings.statusPillForTier(tier), AppColors.statusWarning);
      case DashboardTier.dueToday:
        return (MissionDashboardStrings.statusPillForTier(tier), tokens.brandNavy);
      case DashboardTier.thisWeek:
        return (MissionDashboardStrings.statusPillForTier(tier), tokens.textMuted);
      case DashboardTier.upcoming:
        return (MissionDashboardStrings.statusPillForTier(tier), tokens.textMuted);
    }
  }
}

/// Reason badge for mission queue items.
class MissionReasonBadge extends StatelessWidget {
  const MissionReasonBadge({super.key, required this.item});

  final MissionQueueItem item;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final (bg, fg) = _badgeColors(item.priority, tokens);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        item.reason,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w800,
          color: fg,
        ),
      ),
    );
  }

  (Color, Color) _badgeColors(MissionPriority p, LeapfrogColors tokens) {
    switch (p) {
      case MissionPriority.critical:
        return (tokens.statusCritical.withValues(alpha: 0.15), tokens.statusCritical);
      case MissionPriority.high:
        return (tokens.statusWarning.withValues(alpha: 0.15), tokens.statusWarning);
      case MissionPriority.medium:
        return (tokens.brandNavy.withValues(alpha: 0.12), tokens.brandNavy);
      case MissionPriority.low:
        return (tokens.cardSurfaceMuted, tokens.textMuted);
    }
  }
}

/// Dot + label status indicator (replaces filled pill).
/// Matches the Apon Sushashthya V1 worklist design.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// "Visited" badge shown on completed cards.
class _VisitedBadge extends StatelessWidget {
  const _VisitedBadge({required this.tokens});
  final LeapfrogColors tokens;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.statusSuccess.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.check_circle, size: 11, color: tokens.statusSuccess),
          const SizedBox(width: 3),
          Text(
            'Visited',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: tokens.statusSuccess,
            ),
          ),
        ],
      ),
    );
  }
}
