import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/mission_queue_item.dart';
import '../models/programme.dart';

/// Shared filter category for need-based patient filtering.
/// Used by Dashboard and Patients tab.
enum NeedFilter {
  highRisk,
  ancMnch,
  childImmunisation,
  ncd,
  eyeCare,
  missedFollowUp,
  pendingReferral,
  homeVisit,
  facilityReferral,
}

extension NeedFilterHelpers on NeedFilter {
  String get label {
    switch (this) {
      case NeedFilter.highRisk:
        return MissionDashboardStrings.needHighRisk;
      case NeedFilter.ancMnch:
        return MissionDashboardStrings.needAncMnch;
      case NeedFilter.childImmunisation:
        return MissionDashboardStrings.needChildImmunisation;
      case NeedFilter.ncd:
        return MissionDashboardStrings.needNcd;
      case NeedFilter.eyeCare:
        return MissionDashboardStrings.needEyeCare;
      case NeedFilter.missedFollowUp:
        return MissionDashboardStrings.needMissedFollowUp;
      case NeedFilter.pendingReferral:
        return MissionDashboardStrings.needPendingReferral;
      case NeedFilter.homeVisit:
        return MissionDashboardStrings.needHomeVisit;
      case NeedFilter.facilityReferral:
        return MissionDashboardStrings.needFacilityReferral;
    }
  }

  IconData get icon {
    switch (this) {
      case NeedFilter.highRisk:
        return Icons.warning_amber_rounded;
      case NeedFilter.ancMnch:
        return Icons.pregnant_woman_rounded;
      case NeedFilter.childImmunisation:
        return Icons.child_care_rounded;
      case NeedFilter.ncd:
        return Icons.monitor_heart_rounded;
      case NeedFilter.eyeCare:
        return Icons.visibility_rounded;
      case NeedFilter.missedFollowUp:
        return Icons.event_busy_rounded;
      case NeedFilter.pendingReferral:
        return Icons.assignment_rounded;
      case NeedFilter.homeVisit:
        return Icons.home_rounded;
      case NeedFilter.facilityReferral:
        return Icons.local_hospital_rounded;
    }
  }

  Color get activeColor {
    switch (this) {
      case NeedFilter.highRisk:
        return const Color(0xFFDC2626);
      case NeedFilter.ancMnch:
        return const Color(0xFF831843);
      case NeedFilter.childImmunisation:
        return const Color(0xFF1B2B5E);
      case NeedFilter.ncd:
        return const Color(0xFF854F0B);
      case NeedFilter.eyeCare:
        return const Color(0xFF0E7490);
      case NeedFilter.missedFollowUp:
        return const Color(0xFFD97706);
      case NeedFilter.pendingReferral:
        return const Color(0xFF6B21A8);
      case NeedFilter.homeVisit:
        return const Color(0xFF047857);
      case NeedFilter.facilityReferral:
        return const Color(0xFF0369A1);
    }
  }

  /// Whether this need is satisfied by the given queue item.
  bool matches(MissionQueueItem item) {
    switch (this) {
      case NeedFilter.highRisk:
        return item.priority == MissionPriority.critical ||
            item.priority == MissionPriority.high;
      case NeedFilter.ancMnch:
        return item.programmes
            .any((p) => p == Programme.anc || p == Programme.pnc);
      case NeedFilter.childImmunisation:
        // PILOT-SCOPE v1: imci only (epi not in pilot).
        return item.programmes.contains(Programme.imci);
      case NeedFilter.ncd:
        return item.programmes.contains(Programme.ncd);
      case NeedFilter.eyeCare:
        return item.programmes
            .any((p) => p == Programme.eyeCare || p == Programme.cataract);
      case NeedFilter.missedFollowUp:
        return item.daysOverdue != null && item.daysOverdue! > 0;
      case NeedFilter.pendingReferral:
        return item.referralId != null;
      case NeedFilter.homeVisit:
        return item.type == MissionItemType.patientVisit ||
            item.type == MissionItemType.householdOpportunity;
      case NeedFilter.facilityReferral:
        return item.type == MissionItemType.referral || item.referralId != null;
    }
  }
}

/// Computes which need filters are relevant given a list of queue items.
Set<NeedFilter> computeAvailableNeeds(List<MissionQueueItem> items) {
  final available = <NeedFilter>{};
  for (final item in items) {
    if (item.priority == MissionPriority.critical ||
        item.priority == MissionPriority.high) {
      available.add(NeedFilter.highRisk);
    }
    if (item.programmes.any((p) => p == Programme.anc || p == Programme.pnc)) {
      available.add(NeedFilter.ancMnch);
    }
    if (item.programmes.contains(Programme.imci)) {
      available.add(NeedFilter.childImmunisation);
    }
    if (item.programmes.contains(Programme.ncd)) {
      available.add(NeedFilter.ncd);
    }
    // PILOT-SCOPE v1: eyeCare/cataract chip disabled (not in pilot).
    // if (item.programmes.any((p) => p == Programme.eyeCare || p == Programme.cataract)) {
    //   available.add(NeedFilter.eyeCare);
    // }
    if (item.daysOverdue != null && item.daysOverdue! > 0) {
      available.add(NeedFilter.missedFollowUp);
    }
    if (item.referralId != null) {
      available.add(NeedFilter.pendingReferral);
    }
    if (item.type == MissionItemType.patientVisit ||
        item.type == MissionItemType.householdOpportunity) {
      available.add(NeedFilter.homeVisit);
    }
    if (item.type == MissionItemType.referral || item.referralId != null) {
      available.add(NeedFilter.facilityReferral);
    }
  }
  return available;
}

/// Village option: [value] used for selection logic, [label] shown in the tab.
typedef VillageOption = ({String value, String label});

/// Two-row inline filter panel shared by Dashboard and Patients tab.
///
/// Row 1 — village tabs (tab-underline style)
/// Row 2 — need/programme category bubbles (multi-select)
class PatientFilterPanel extends StatelessWidget {
  const PatientFilterPanel({
    super.key,
    required this.villages,
    required this.selectedVillageValue,
    required this.onVillageSelected,
    required this.availableNeeds,
    required this.selectedNeeds,
    required this.onNeedToggled,
    required this.onClearNeeds,
  });

  final List<VillageOption> villages;
  final String? selectedVillageValue;
  final void Function(String? value) onVillageSelected;
  final Set<NeedFilter> availableNeeds;
  final Set<NeedFilter> selectedNeeds;
  final void Function(NeedFilter need) onNeedToggled;
  final VoidCallback onClearNeeds;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: village tabs ───────────────────────────────────────────
        if (villages.isNotEmpty) ...[
          SizedBox(
            height: 38,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                VillageFilterTab(
                  label: MissionDashboardStrings.allVillages,
                  isActive: selectedVillageValue == null,
                  onTap: () => onVillageSelected(null),
                ),
                ...villages.map((v) => VillageFilterTab(
                      label: v.label,
                      isActive: selectedVillageValue == v.value,
                      onTap: () => onVillageSelected(
                          selectedVillageValue == v.value ? null : v.value),
                    )),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Divider(
              height: 1,
              color: Theme.of(context).colorScheme.outlineVariant),
          const SizedBox(height: 10),
        ],

        // ── Row 2: clear filters (only when active) ───────────────────────
        if (selectedNeeds.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Align(
              alignment: Alignment.centerRight,
              child: Semantics(
                label: 'Clear all filters',
                button: true,
                child: GestureDetector(
                  onTap: onClearNeeds,
                  child: Text(
                    MissionDashboardStrings.clearNeedFilters,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ),
              ),
            ),
          ),

        // ── Row 3: category bubbles ──────────────────────────────────────────
        if (availableNeeds.isNotEmpty)
          SizedBox(
            height: 88,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              children: [
                ...NeedFilter.values
                    .where((n) => availableNeeds.contains(n))
                    .map((need) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: NeedCategoryBubble(
                            label: need.label,
                            icon: need.icon,
                            activeColor: need.activeColor,
                            isActive: selectedNeeds.contains(need),
                            onTap: () => onNeedToggled(need),
                          ),
                        )),
              ],
            ),
          ),
      ],
    );
  }
}

/// Tab-style village selector used inside [PatientFilterPanel].
class VillageFilterTab extends StatelessWidget {
  const VillageFilterTab({
    super.key,
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const activeColor = Color(0xFF1B2B5E);
    const activeLine = Color(0xFFEC4899);
    return GestureDetector(
      key: const Key('patient_filter_village_tap'),
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(right: 16),
        padding: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeLine : Colors.transparent,
              width: 2,
            ),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
            color: isActive ? activeColor : const Color(0xFF6B7280),
          ),
        ),
      ),
    );
  }
}

/// Circular category bubble used inside [PatientFilterPanel].
class NeedCategoryBubble extends StatelessWidget {
  const NeedCategoryBubble({
    super.key,
    required this.label,
    required this.icon,
    required this.activeColor,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color activeColor;
  final bool isActive;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Semantics(
      label: isActive ? '$label filter, selected' : 'Filter by $label',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox(
          width: 68,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isActive ? activeColor : cs.surface,
                  border: Border.all(
                    color: isActive ? activeColor : cs.outlineVariant,
                    width: 1.5,
                  ),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: activeColor.withValues(alpha: 0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 2),
                          )
                        ]
                      : null,
                ),
                child: Icon(
                  icon,
                  size: 22,
                  color: isActive ? Colors.white : cs.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                label,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  color: isActive ? activeColor : cs.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
