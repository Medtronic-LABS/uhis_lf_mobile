import 'package:flutter/material.dart';

import '../constants/app_strings.dart';
import '../models/dashboard_tier.dart';
import '../models/mission_queue_item.dart';
import '../models/programme.dart';
import '../theme/app_theme.dart';

/// Normalizes a raw, inconsistently-cased place name (village/sub-village
/// data as synced, often all-caps) to title case for display.
String titleCaseWords(String s) => s
    .split(' ')
    .map((w) => w.isEmpty ? w : w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

/// Shared filter category for need-based patient filtering.
/// Used by Dashboard and Patients tab.
enum NeedFilter {
  highRisk,
  ancMnch,
  childImmunisation,
  ncd,
  eyeCare,
  thisWeek,
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
      case NeedFilter.thisWeek:
        return MissionDashboardStrings.needThisWeek;
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

  // v13 cat-bubble-icon glyph — literal emoji, matches the mockup exactly.
  String get emoji {
    switch (this) {
      case NeedFilter.highRisk:
        return '⚠️';
      case NeedFilter.ancMnch:
        return '🤰';
      case NeedFilter.childImmunisation:
        return '👶';
      case NeedFilter.ncd:
        return '💊';
      case NeedFilter.eyeCare:
        return '👁️';
      case NeedFilter.thisWeek:
        return '📅';
      case NeedFilter.missedFollowUp:
        return '⏰';
      case NeedFilter.pendingReferral:
        return '📋';
      case NeedFilter.homeVisit:
        return '🏠';
      case NeedFilter.facilityReferral:
        return '🏥';
    }
  }

  // v13 border accent colors (--bcolor per category)
  Color get activeColor {
    switch (this) {
      case NeedFilter.highRisk:          return AppColors.statusCritical;
      case NeedFilter.ancMnch:           return AppColors.pinkWorklist;
      case NeedFilter.childImmunisation: return AppColors.statusWarning;
      case NeedFilter.ncd:               return AppColors.catNcdBorder;
      case NeedFilter.eyeCare:           return AppColors.infoAccent;
      case NeedFilter.thisWeek:          return AppColors.statusWarning;
      case NeedFilter.missedFollowUp:    return AppColors.textMuted;
      case NeedFilter.pendingReferral:   return AppColors.catReferralBorder;
      case NeedFilter.homeVisit:         return AppColors.statusSuccess;
      case NeedFilter.facilityReferral:  return AppColors.catFacilityBorder;
    }
  }

  // v13 surface tint colors (--bbg per category)
  Color get activeSurface {
    switch (this) {
      case NeedFilter.highRisk:          return AppColors.catHighriskSurface;
      case NeedFilter.ancMnch:           return AppColors.ancSurface;
      case NeedFilter.childImmunisation: return AppColors.catChildSurface;
      case NeedFilter.ncd:               return AppColors.catNcdSurface;
      // #EFF6FF == AppColors.childSurface — value shared with the programme
      // "child" token, not semantically related to eye care.
      case NeedFilter.eyeCare:           return AppColors.childSurface;
      case NeedFilter.thisWeek:          return AppColors.statusWarningSurface;
      case NeedFilter.missedFollowUp:    return AppColors.catMissedSurface;
      // #F5F3FF == AppColors.pncSurface — value shared with the programme
      // "PNC" token, not semantically related to referrals.
      case NeedFilter.pendingReferral:   return AppColors.pncSurface;
      case NeedFilter.homeVisit:         return AppColors.catHomeSurface;
      case NeedFilter.facilityReferral:  return AppColors.catFacilitySurface;
    }
  }

  /// Whether this need is satisfied by the given queue item.
  bool matches(MissionQueueItem item) {
    switch (this) {
      case NeedFilter.highRisk:
        return item.priority == MissionPriority.critical ||
            item.priority == MissionPriority.high;
      case NeedFilter.ancMnch:
        // PWPROFILE is pregnancy enrolment (anc+pw flow) — must match ANC/MNCH
        // or PW-only patients never appear when the SK selects this chip (#158).
        return item.programmes.any(
          (p) =>
              p == Programme.anc || p == Programme.pnc || p == Programme.pw,
        );
      case NeedFilter.childImmunisation:
        // PILOT-SCOPE v1: imci only (epi not in pilot).
        return item.programmes.contains(Programme.imci);
      case NeedFilter.ncd:
        return item.programmes.contains(Programme.ncd);
      case NeedFilter.eyeCare:
        return item.programmes
            .any((p) => p == Programme.eyeCare || p == Programme.cataract);
      case NeedFilter.thisWeek:
        // Calendar schedule 1–7 days out — not clinical tier (may be critical).
        return DashboardTier.fromDueAt(item.dueAt) == DashboardTier.thisWeek;
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
    if (item.programmes.any(
      (p) => p == Programme.anc || p == Programme.pnc || p == Programme.pw,
    )) {
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
    if (DashboardTier.fromDueAt(item.dueAt) == DashboardTier.thisWeek) {
      available.add(NeedFilter.thisWeek);
    }
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

/// Programme-category need chips (ANC/MNCH, child, NCD, eye).
bool isProgrammeNeedFilter(NeedFilter need) {
  switch (need) {
    case NeedFilter.ancMnch:
    case NeedFilter.childImmunisation:
    case NeedFilter.ncd:
    case NeedFilter.eyeCare:
      return true;
    case NeedFilter.highRisk:
    case NeedFilter.thisWeek:
    case NeedFilter.missedFollowUp:
    case NeedFilter.pendingReferral:
    case NeedFilter.homeVisit:
    case NeedFilter.facilityReferral:
      return false;
  }
}

/// Schedule chips (This week) — keep completed-today so due-in-1–7 Done
/// patients still appear under the filter.
bool isScheduleNeedFilter(NeedFilter need) => need == NeedFilter.thisWeek;

/// Apply village / need / search filters to a mission queue.
///
/// When a programme or schedule need chip is selected:
/// - [upcoming] patients are kept (#158 / This week)
/// - completed-today patients are kept (done on cards) so e.g. Yasmeen
///   (due tomorrow, visited today) is not missing
/// - completed-today are restacked **after** still-open visits
///
/// Otherwise upcoming + completed-today are dropped — the unfiltered dashboard
/// only shows actionable Today / Overdue / This week.
List<MissionQueueItem> filterMissionQueue({
  required List<MissionQueueItem> queue,
  String? village,
  Set<NeedFilter> selectedNeeds = const {},
  String searchQuery = '',
  Set<String> completedPatientIds = const {},
}) {
  var result = List<MissionQueueItem>.from(queue);
  final stages = <String>['in=${result.length}'];

  final keepExpanded = selectedNeeds.any(isProgrammeNeedFilter) ||
      selectedNeeds.any(isScheduleNeedFilter);

  if (!keepExpanded) {
    result = result
        .where((i) => i.tier != DashboardTier.upcoming)
        .toList(growable: false);
    stages.add('afterUpcomingDrop=${result.length}');

    if (completedPatientIds.isNotEmpty) {
      result = result
          .where(
            (i) =>
                i.patientId == null ||
                !completedPatientIds.contains(i.patientId),
          )
          .toList(growable: false);
      stages.add('afterCompletedDrop=${result.length}');
    }
  } else {
    stages.add('upcoming+completedKept(needChip)');
  }

  final chipVillage = village?.trim();
  if (chipVillage != null && chipVillage.isNotEmpty) {
    final needle = chipVillage.toLowerCase();
    result = result
        .where((i) => (i.village?.trim().toLowerCase() ?? '') == needle)
        .toList();
    stages.add('afterVillage("$chipVillage")=${result.length}');
  }

  if (selectedNeeds.isNotEmpty) {
    result = result
        .where((item) => selectedNeeds.any((need) => need.matches(item)))
        .toList();
    stages.add(
      'afterNeeds([${selectedNeeds.map((n) => n.name).join(",")}])='
      '${result.length}',
    );
  }

  final q = searchQuery.trim().toLowerCase();
  if (q.isNotEmpty) {
    result = result
        .where(
          (i) =>
              i.patientName.toLowerCase().contains(q) ||
              (i.phoneNumber?.contains(q) ?? false) ||
              (i.nid?.toLowerCase().contains(q) ?? false),
        )
        .toList();
    stages.add('afterSearch="$q"=${result.length}');
  }

  // Open visits first (existing priority order), completed-today at bottom.
  if (keepExpanded && completedPatientIds.isNotEmpty) {
    final open = <MissionQueueItem>[];
    final done = <MissionQueueItem>[];
    for (final i in result) {
      final isDone =
          i.patientId != null && completedPatientIds.contains(i.patientId);
      if (isDone) {
        done.add(i);
      } else {
        open.add(i);
      }
    }
    if (done.isNotEmpty) {
      result = [...open, ...done];
      stages.add('doneAtBottom(open=${open.length},done=${done.length})');
    }
  }

  assert(() {
    final needLabels = selectedNeeds.isEmpty
        ? '(none)'
        : selectedNeeds.map((n) => n.name).join(',');
    debugPrint(
      '[Dashboard filter] village=${chipVillage ?? "(all)"} '
      'needs=[$needLabels] search="${searchQuery.trim()}"',
    );
    debugPrint('[Dashboard filter] ${stages.join(" → ")}');
    debugPrint(
      '[Dashboard filter] kept: '
      '${result.take(12).map((i) {
        final done = i.patientId != null &&
            completedPatientIds.contains(i.patientId);
        return '${i.patientName}[${i.priorityCode}]'
            '/${i.programmes.map((p) => p.name).join("+")}'
            '/v=${i.village ?? "-"}'
            '${done ? "/DONE" : ""}';
      }).join(" | ")}'
      '${result.length > 12 ? " | …+${result.length - 12}" : ""}',
    );

    for (final probe in const [
      'Yasmeen',
      'Raaajasri',
      'Teena',
      'Nazmeen',
      'Jakir',
    ]) {
      MissionQueueItem? item;
      for (final i in queue) {
        if (i.patientName == probe) {
          item = i;
          break;
        }
      }
      if (item == null) {
        debugPrint('[Dashboard filter] probe $probe → not in base queue');
        continue;
      }
      final drop = <String>[];
      final done = item.patientId != null &&
          completedPatientIds.contains(item.patientId);
      if (!keepExpanded && item.tier == DashboardTier.upcoming) {
        drop.add('upcoming-tier');
      }
      if (!keepExpanded && done) {
        drop.add('completedToday');
      }
      if (chipVillage != null &&
          chipVillage.isNotEmpty &&
          (item.village?.trim().toLowerCase() ?? '') !=
              chipVillage.toLowerCase()) {
        drop.add('village("${item.village}"≠"$chipVillage")');
      }
      if (selectedNeeds.isNotEmpty) {
        final needHits = <String>[];
        var any = false;
        for (final n in selectedNeeds) {
          final hit = n.matches(item);
          needHits.add('${n.name}=${hit ? "Y" : "N"}');
          if (hit) any = true;
        }
        if (!any) {
          drop.add(
            'needs(${needHits.join(",")}; '
            'prog=${item.programmes.map((p) => p.name).join("+")})',
          );
        }
      }
      if (q.isNotEmpty &&
          !item.patientName.toLowerCase().contains(q) &&
          !(item.phoneNumber?.contains(q) ?? false) &&
          !(item.nid?.toLowerCase().contains(q) ?? false)) {
        drop.add('search');
      }
      if (drop.isEmpty) {
        debugPrint(
          '[Dashboard filter] probe $probe → KEEP '
          '[${item.priorityCode}] v=${item.village} '
          'prog=${item.programmes.map((p) => p.name).join("+")}'
          '${done ? " DONE-today" : ""}',
        );
      } else {
        debugPrint(
          '[Dashboard filter] probe $probe → DROP ${drop.join("; ")}',
        );
      }
    }
    return true;
  }());

  return result;
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
  });

  final List<VillageOption> villages;
  final String? selectedVillageValue;
  final void Function(String? value) onVillageSelected;
  final Set<NeedFilter> availableNeeds;
  final Set<NeedFilter> selectedNeeds;
  final void Function(NeedFilter need) onNeedToggled;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Row 1: village tabs ───────────────────────────────────────────
        if (villages.isNotEmpty) ...[
          DecoratedBox(
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1.5),
              ),
            ),
            child: SizedBox(
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
                        label: titleCaseWords(v.label),
                        isActive: selectedVillageValue == v.value,
                        onTap: () => onVillageSelected(
                            selectedVillageValue == v.value ? null : v.value),
                      )),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
        ],

        // ── Row 2: category bubbles ──────────────────────────────────────────
        SizedBox(
          height: 88,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.zero,
            children: [
              ...(() {
                final active =
                    NeedFilter.values.where((n) => availableNeeds.contains(n)).toList();
                final disabled =
                    NeedFilter.values.where((n) => !availableNeeds.contains(n)).toList();
                return [...active, ...disabled];
              })()
                  .map((need) {
                final dis = !availableNeeds.contains(need);
                return Padding(
                  padding: const EdgeInsets.only(right: 11),
                  child: NeedCategoryBubble(
                    label: need.label,
                    emoji: need.emoji,
                    activeColor: need.activeColor,
                    activeSurface: need.activeSurface,
                    isActive: selectedNeeds.contains(need),
                    isDisabled: dis,
                    onTap: () => onNeedToggled(need),
                  ),
                );
              }),
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
    this.fontWeight,
  });

  final String label;
  final bool isActive;
  final VoidCallback onTap;

  /// Overrides `AppTextStyles.villageTab`'s weight for this instance only —
  /// null (the default) keeps every existing call site (the Home dashboard)
  /// unchanged.
  final FontWeight? fontWeight;

  @override
  Widget build(BuildContext context) {
    final activeLine = Theme.of(context)
            .extension<WorklistCategoryColors>()
            ?.villageTabIndicator ??
        AppColors.pinkWorklist;
    return GestureDetector(
      key: const Key('patient_filter_village_tap'),
      onTap: onTap,
      child: AnimatedContainer(
        duration: AppAnimations.control,
        curve: AppAnimations.standard,
        margin: const EdgeInsets.only(right: 18),
        padding: const EdgeInsets.fromLTRB(1, 8, 1, 9),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: isActive ? activeLine : Colors.transparent,
              width: 2.5,
            ),
          ),
        ),
        child: AnimatedDefaultTextStyle(
          duration: AppAnimations.control,
          curve: AppAnimations.standard,
          style: AppTextStyles.villageTab.copyWith(
            color: isActive ? AppColors.navy : AppColors.textMuted,
            fontWeight: fontWeight,
          ),
          child: Text(label),
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
    required this.emoji,
    required this.activeColor,
    required this.activeSurface,
    required this.isActive,
    required this.onTap,
    this.isDisabled = false,
  });

  final String label;
  final String emoji;
  final Color activeColor;   // border accent (--bcolor)
  final Color activeSurface; // surface tint  (--bbg)
  final bool isActive;
  final bool isDisabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: isDisabled
          ? '$label filter, unavailable'
          : isActive
              ? '$label filter, selected'
              : 'Filter by $label',
      button: true,
      child: Opacity(
        opacity: isDisabled ? 0.45 : 1.0,
        child: GestureDetector(
          onTap: isDisabled ? null : onTap,
          child: SizedBox(
            width: 58,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: AppAnimations.control,
                  curve: AppAnimations.standard,
                  alignment: Alignment.center,
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isActive ? activeSurface : AppColors.cardSurface,
                    border: Border.all(
                      color: isActive ? activeColor : AppColors.border,
                      width: 2,
                    ),
                    boxShadow: isActive
                        ? const [
                            BoxShadow(
                              color: Color(0x14000000),
                              blurRadius: 6,
                              offset: Offset(0, 2),
                            )
                          ]
                        : null,
                  ),
                  // Literal emoji glyph — matches the mockup's .cat-bubble-icon
                  // exactly. No color applied: emoji are full-color glyphs and
                  // ignore TextStyle.color, same as the mockup itself never
                  // recolors this element on .active.
                  child: Text(
                    emoji,
                    style: const TextStyle(fontSize: 19),
                  ),
                ),
                const SizedBox(height: 5),
                AnimatedDefaultTextStyle(
                  duration: AppAnimations.control,
                  curve: AppAnimations.standard,
                  style: AppTextStyles.categoryBubbleLabel.copyWith(
                    color: isActive ? AppColors.textPrimary : AppColors.textMuted,
                  ),
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
