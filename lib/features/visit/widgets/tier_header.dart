import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/models/dashboard_tier.dart';

/// Header row for a tier section in the visit list.
/// Used by both Dashboard (home) and Tasks screens.
class MissionTierHeader extends StatelessWidget {
  const MissionTierHeader({
    super.key,
    required this.tier,
    required this.count,
    this.compact = false,
  });

  final DashboardTier tier;
  final int count;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final urgency = Theme.of(context).extension<UrgencyTheme>()!;
    final color = _tierColor(tier, urgency, tokens);
    final label = MissionDashboardStrings.tierLabel(tier).toUpperCase();

    if (compact) {
      // Compact style used by dashboard
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            MissionDashboardStrings.tierHeaderWithCount(tier, count),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      );
    }

    // Full style used by tasks screen
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _tierColor(
    DashboardTier tier,
    UrgencyTheme urgency,
    LeapfrogColors tokens,
  ) {
    switch (tier) {
      case DashboardTier.critical:
        return urgency.visitNow;    // red
      case DashboardTier.overdue:
        return urgency.today;        // amber — was visitNow (red), now distinct from critical
      case DashboardTier.dueToday:
        return tokens.statusSuccess; // green
      case DashboardTier.thisWeek:
        return urgency.thisWeek;
      case DashboardTier.upcoming:
        return tokens.textMuted;
    }
  }
}

/// Header for completed visits section.
class CompletedTierHeader extends StatelessWidget {
  const CompletedTierHeader({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 20,
            decoration: BoxDecoration(
              color: tokens.statusSuccess,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: tokens.statusSuccess,
          ),
          const SizedBox(width: 6),
          Text(
            'COMPLETED TODAY',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: tokens.statusSuccess,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: tokens.statusSuccess.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: tokens.statusSuccess,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
