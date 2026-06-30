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
    final (actionLabel, actionBg, actionFg) = isCompleted
        ? ('Done', tokens.statusSuccess.withValues(alpha: 0.15), tokens.statusSuccess)
        : _statusPillStyle(item.tier, tokens);

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
                border: Border(
                  left: BorderSide(color: borderColor, width: 4),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
              child: Row(
                children: [
                  // Avatar colour-coded by programme (pink=ANC, yellow=NCD)
                  CircleAvatar(
                    radius: 22,
                    backgroundColor: isCompleted
                        ? tokens.statusSuccess.withValues(alpha: 0.18)
                        : avatarColor.withValues(alpha: 0.15),
                    child: isCompleted
                        ? Icon(
                            Icons.check,
                            color: tokens.statusSuccess,
                            size: 24,
                          )
                        : Text(
                            _initials(item.patientName),
                            style: TextStyle(
                              color: isCompleted
                                  ? tokens.statusSuccess
                                  : avatarColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                            ),
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
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
                            if (isCompleted)
                              Container(
                                margin: const EdgeInsets.only(left: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: tokens.statusSuccess.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.check_circle,
                                      size: 12,
                                      color: tokens.statusSuccess,
                                    ),
                                    const SizedBox(width: 4),
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
                              ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        MissionReasonBadge(item: item),
                        if (item.drivers.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          _DriverChip(
                            label: MissionDashboardStrings
                                .driverLabel(item.drivers.first),
                            color: borderColor,
                          ),
                        ],
                        const SizedBox(height: 6),
                        Text(
                          _subtitle(item),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: tokens.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!isCompleted && showActionButton)
                    Semantics(
                      label: 'Start visit for ${item.patientName}',
                      button: true,
                      child: Material(
                      color: actionBg,
                      borderRadius: BorderRadius.circular(20),
                      child: InkWell(
                        key: const Key('visit_queue_card_action_tap'),
                        borderRadius: BorderRadius.circular(20),
                        onTap: onAction,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                          child: Text(
                            actionLabel,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: actionFg,
                            ),
                          ),
                        ),
                      ),
                    ),
                    )
                  else if (isCompleted)
                    Icon(
                      Icons.check_circle_rounded,
                      color: tokens.statusSuccess,
                      size: 28,
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

  /// Border colour rule — Apon Sushashthya V1 §2.6.
  ///
  /// Default: neutral grey (#E5E7EB) — reduces visual noise on routine
  /// visits. Red border applies ONLY to Band 1 cards when a CCE alert is
  /// active (driver `sla-breached`) OR a clinical danger sign is present
  /// (driver `danger-sign`, `stroke-sign`, or `eclampsia`). A Band 1 patient
  /// flagged purely on labs (severe anaemia, BP ≥ 160/110) without a
  /// danger-sign driver keeps the grey border so the worklist stays calm.
  Color _borderColorForTier(DashboardTier tier, LeapfrogColors tokens) {
    if (tier != DashboardTier.critical) return const Color(0xFFE5E7EB);
    final drivers = item.drivers;
    final cceOrDanger = drivers.contains('sla-breached') ||
        drivers.contains('danger-sign') ||
        drivers.contains('stroke-sign') ||
        drivers.contains('eclampsia');
    return cceOrDanger ? tokens.statusCritical : const Color(0xFFE5E7EB);
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

  /// Status pill style: (label, background, foreground) keyed by tier.
  (String, Color, Color) _statusPillStyle(
    DashboardTier tier,
    LeapfrogColors tokens,
  ) {
    switch (tier) {
      case DashboardTier.critical:
        return (
          MissionDashboardStrings.statusPillForTier(tier),
          tokens.statusCritical,
          Colors.white,
        );
      case DashboardTier.overdue:
        return (
          MissionDashboardStrings.statusPillForTier(tier),
          AppColors.statusWarning,
          Colors.white,
        );
      case DashboardTier.dueToday:
        return (
          MissionDashboardStrings.statusPillForTier(tier),
          tokens.brandNavy,
          Colors.white,
        );
      case DashboardTier.thisWeek:
        return (
          MissionDashboardStrings.statusPillForTier(tier),
          tokens.cardSurfaceMuted,
          tokens.brandNavy,
        );
      case DashboardTier.upcoming:
        return (
          MissionDashboardStrings.statusPillForTier(tier),
          tokens.cardSurfaceMuted,
          tokens.textMuted,
        );
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

/// Small chip rendering the first driver tag on a [MissionQueueItem] so the
/// SK can see *why* the card landed in its tier (e.g. `'Referral pending
/// arrival'`, `'Neonate (under 28 days)'`, `'Lost-to-follow-up streak'`).
/// Borrowed color from the card's border so it visually inherits the tier
/// urgency cue.
class _DriverChip extends StatelessWidget {
  const _DriverChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.35), width: 0.8),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
