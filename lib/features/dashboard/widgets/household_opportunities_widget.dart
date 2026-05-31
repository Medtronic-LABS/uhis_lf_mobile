import 'package:flutter/material.dart';

import '../../../core/constants/app_strings.dart';
import '../../../core/models/mission_queue_item.dart';

/// Household Opportunities Widget — bundled services in one visit.
///
/// Shows households where multiple family members need services,
/// enabling efficient multi-service visits.
///
/// Spec: AI Mission Dashboard (Screen 2) — Section 8.
class HouseholdOpportunitiesWidget extends StatelessWidget {
  const HouseholdOpportunitiesWidget({
    super.key,
    required this.opportunities,
    this.onVisitHousehold,
    this.onViewAll,
  });

  final List<HouseholdOpportunity> opportunities;
  final void Function(HouseholdOpportunity)? onVisitHousehold;
  final VoidCallback? onViewAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (opportunities.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.3),
        ),
      ),
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
                    color: scheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    Icons.home_work,
                    color: scheme.primary,
                    size: 16,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        MissionDashboardStrings.householdOpportunities,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                      ),
                      Row(
                        children: [
                          Icon(
                            Icons.auto_awesome,
                            size: 10,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AI-identified multi-service visits',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: scheme.primary,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (opportunities.length > 2)
                  TextButton(
                    onPressed: onViewAll,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('View all', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // Opportunity cards
            ...opportunities.take(2).map((opp) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _HouseholdOpportunityCard(
                    opportunity: opp,
                    onVisit: onVisitHousehold != null
                        ? () => onVisitHousehold!(opp)
                        : null,
                  ),
                )),
          ],
        ),
      ),
    );
  }
}

class _HouseholdOpportunityCard extends StatelessWidget {
  const _HouseholdOpportunityCard({
    required this.opportunity,
    this.onVisit,
  });

  final HouseholdOpportunity opportunity;
  final VoidCallback? onVisit;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: scheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Household header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.home,
                  color: scheme.primary,
                  size: 14,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      opportunity.householdName ??
                          MissionDashboardStrings.householdNumber(
                            opportunity.householdNumber,
                          ),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                    Text(
                      MissionDashboardStrings.potentialServicesCount(
                        opportunity.potentialServicesCount,
                      ),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                    ),
                  ],
                ),
              ),
              FilledButton.tonal(
                onPressed: onVisit,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.directions_walk, size: 14),
                    const SizedBox(width: 4),
                    Text(MissionDashboardStrings.visitHousehold),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 8),

          // Member services
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: opportunity.memberServices.entries.map((entry) {
              return _ServiceChip(
                role: entry.key,
                service: entry.value,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }
}

class _ServiceChip extends StatelessWidget {
  const _ServiceChip({
    required this.role,
    required this.service,
  });

  final String role;
  final String service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (emoji, color) = _roleInfo(role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: color.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                role,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: color,
                      fontSize: 10,
                    ),
              ),
              Text(
                service,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface,
                      fontSize: 10,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  (String, Color) _roleInfo(String role) {
    final lower = role.toLowerCase();
    if (lower.contains('mother') || lower.contains('wife')) {
      return ('👩', const Color(0xFFEC4899)); // pink
    }
    if (lower.contains('father') || lower.contains('husband')) {
      return ('👨', const Color(0xFF3B82F6)); // blue
    }
    if (lower.contains('child') || lower.contains('son') || lower.contains('daughter')) {
      return ('👶', const Color(0xFF22C55E)); // green
    }
    if (lower.contains('elder') || lower.contains('grand')) {
      return ('👴', const Color(0xFF6B7280)); // gray
    }
    return ('👤', const Color(0xFF6B7280));
  }
}
