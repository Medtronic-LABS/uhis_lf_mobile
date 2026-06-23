import 'package:flutter/material.dart';

import '../../../app/theme.dart';
import '../../../core/models/dashboard_tier.dart';

/// Chip for filtering visits by tier.
/// Used by the Tasks screen's Visits tab.
class VisitTierChip extends StatelessWidget {
  const VisitTierChip({
    super.key,
    required this.label,
    required this.count,
    required this.tier,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final int count;
  final DashboardTier? tier;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).extension<LeapfrogColors>()!;
    final color = _tierColor(tier, tokens);
    return GestureDetector(
      key: const Key('visit_tier_chip_tap'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? color : tokens.textMuted.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected ? color : tokens.textMuted,
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected ? color : tokens.textMuted.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: isSelected ? Colors.white : tokens.textMuted,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Color _tierColor(DashboardTier? tier, LeapfrogColors tokens) {
    if (tier == null) return tokens.brandNavy;
    switch (tier) {
      case DashboardTier.critical:
        return tokens.statusCritical;
      case DashboardTier.overdue:
        return tokens.statusWarning;
      case DashboardTier.dueToday:
        return tokens.statusInfo;
      case DashboardTier.thisWeek:
        return tokens.brandNavy;
      case DashboardTier.upcoming:
        return tokens.textMuted;
    }
  }
}
