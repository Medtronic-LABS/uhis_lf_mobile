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
    final programmeColor = isCompleted
        ? tokens.statusSuccess
        : _programmeColor(item);
    final tierBorderColor = isCompleted
        ? tokens.statusSuccess
        : _borderColorForTier(item.tier, tokens);
    final hasTierBorder = tierBorderColor != const Color(0xFFE5E7EB);
    final (dotLabel, dotColor) = isCompleted
        ? ('Done', tokens.statusSuccess)
        : _statusDotStyle(item.tier, tokens);

    return Opacity(
      opacity: isCompleted ? 0.6 : 1.0,
      child: Padding(
        padding: compact
            ? EdgeInsets.zero
            : const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Semantics(
          label: 'View patient ${item.patientName}',
          button: true,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: tokens.cardSurface,
              boxShadow: [
                // Subtle programme-colour glow on the left
                BoxShadow(
                  color: programmeColor.withValues(alpha: 0.22),
                  offset: const Offset(-5, 0),
                  blurRadius: 12,
                  spreadRadius: 0,
                ),
                // Standard card drop shadow
                BoxShadow(
                  color: const Color(0xFF000000).withValues(alpha: 0.06),
                  offset: const Offset(0, 2),
                  blurRadius: 6,
                ),
              ],
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(12),
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
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: hasTierBorder
                        ? Border(
                            left: BorderSide(color: tierBorderColor, width: 4),
                          )
                        : const Border(
                            left: BorderSide(
                              color: Color(0xFFE5E7EB),
                              width: 4,
                            ),
                          ),
                  ),
                  padding: const EdgeInsets.fromLTRB(13, 11, 12, 11),
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // ── Content ──────────────────────────────────────────
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Row 1: Name + age chip + reason badge (wraps)
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 6,
                            runSpacing: 3,
                            children: [
                              Text(
                                item.patientName,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w800,
                                  color: isCompleted
                                      ? tokens.textMuted
                                      : tokens.textPrimary,
                                  decoration: isCompleted
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              ),
                              if (item.age != null) _AgeChip(item.age!),
                              if (isCompleted)
                                _VisitedBadge(tokens: tokens)
                              else
                                MissionReasonBadge(item: item),
                            ],
                          ),
                          const SizedBox(height: 4),

                          // Row 2: address
                          Builder(builder: (context) {
                            final address = [
                              item.householdDisplay,
                              item.village ?? '',
                            ].where((s) => s.isNotEmpty).join(', ');
                            if (address.isEmpty) return const SizedBox.shrink();
                            return Row(
                              children: [
                                Icon(Icons.home_outlined, size: 12, color: tokens.textMuted),
                                const SizedBox(width: 4),
                                Flexible(
                                  child: Text(
                                    address,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
                                  ),
                                ),
                              ],
                            );
                          }),

                          // Row 3: phone (if available)
                          if (item.phoneNumber != null && item.phoneNumber!.isNotEmpty) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.phone_outlined, size: 12, color: tokens.textMuted),
                                const SizedBox(width: 4),
                                Text(
                                  item.phoneNumber!,
                                  style: TextStyle(fontSize: 11.5, color: tokens.textMuted),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(width: 10),

                    // ── Status dot + label ───────────────────────────────
                    _StatusDot(label: dotLabel, color: dotColor),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  }


  /// Programme accent colour — drives avatar tint only (left border stays grey).
  static Color _programmeColor(MissionQueueItem item) {
    if (item.programmes.contains(Programme.anc) ||
        item.programmes.contains(Programme.pnc)) {
      return const Color(0xFF831843); // deep rose — pregnancy
    }
    if (item.programmes.contains(Programme.imci) ||
        item.programmes.contains(Programme.epi)) {
      return const Color(0xFF1B2B5E); // navy — child / immunisation
    }
    if (item.programmes.contains(Programme.ncd)) {
      return const Color(0xFF854F0B); // deep amber — NCD
    }
    if (item.programmes.contains(Programme.tb)) return AppColors.aiPurple;
    return const Color(0xFF6B7280); // grey — unenrolled / unknown
  }

  /// Tier border overrides programme color for urgent states (overdue / CCE).
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

// ─── Age chip ─────────────────────────────────────────────────────────────────

class _AgeChip extends StatelessWidget {
  const _AgeChip(this.age);
  final int age;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: tokens.brandNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '${age}y',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: tokens.brandNavy,
        ),
      ),
    );
  }
}

// ─── Reason badge ─────────────────────────────────────────────────────────────

/// Service-needed pill shown next to patient name.
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
          fontWeight: FontWeight.w700,
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

// ─── Status dot ───────────────────────────────────────────────────────────────

/// Dot + label status indicator.
class _StatusDot extends StatelessWidget {
  const _StatusDot({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
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
        ),
      ],
    );
  }
}

// ─── Visited badge ────────────────────────────────────────────────────────────

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
