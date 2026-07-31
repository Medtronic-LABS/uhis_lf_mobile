import 'epi_schedule_engine.dart';

/// Vaccine-aware summary of an EPI/child-immunisation visit, derived from the
/// [VaccineMilestone] list already computed by [EpiScheduleEngine.build] for
/// the vaccination timeline. Bridges that pure schedule data into the visit
/// flow's Step 3 (AI recommendation) so referral banners, counselling text,
/// and the follow-up date reflect the vaccines actually due — instead of the
/// generic "routine care plan" text Step 3 falls back to for programmes it
/// has no specific data for.
class EpiVisitSummary {
  const EpiVisitSummary({
    required this.overdueCount,
    required this.overdueVaccineNames,
    required this.currentMilestoneLabel,
    this.nextMilestoneLabel,
    this.nextMilestoneDate,
    this.nextMilestoneVaccineNames = const [],
  });

  /// Count of vaccines currently due (status [VaccineStatus.dueNow]) across
  /// every milestone that has at least one due vaccine. Matches
  /// `ImmunisationTimelineScreen._totalOverdueCount` so this number is
  /// consistent with what the SK just saw on the vaccination timeline.
  final int overdueCount;

  /// Display names of every due vaccine, flattened across all milestones
  /// that currently have one or more due vaccines (a real catch-up scenario
  /// can have two milestones simultaneously due).
  final List<String> overdueVaccineNames;

  /// Label of the milestone driving [overdueCount] (e.g. "14 Weeks") — the
  /// chronologically-latest milestone with a due vaccine, when more than one
  /// qualifies. Empty string when [overdueCount] is zero.
  final String currentMilestoneLabel;

  /// Label of the next not-yet-completed milestone after the current one
  /// (e.g. "9 Months"), or null if none remain.
  final String? nextMilestoneLabel;

  /// Scheduled date of [nextMilestoneLabel]'s milestone.
  final DateTime? nextMilestoneDate;

  /// Vaccine display names due at [nextMilestoneLabel].
  final List<String> nextMilestoneVaccineNames;

  bool get referralWarranted => overdueCount > 0;
}

/// Builds an [EpiVisitSummary] from the milestone list the vaccination
/// timeline already computed. Pure function — no I/O, no Flutter deps.
EpiVisitSummary buildEpiVisitSummary(List<VaccineMilestone> milestones) {
  final dueMilestones = milestones.where((m) => m.hasDueNow).toList();

  final overdueVaccineNames = dueMilestones
      .expand((m) => m.vaccines)
      .where((v) => v.status == VaccineStatus.dueNow)
      .map((v) => v.display)
      .toList();

  final currentMilestone = dueMilestones.isNotEmpty ? dueMilestones.last : null;

  final searchFrom =
      currentMilestone != null ? milestones.indexOf(currentMilestone) + 1 : 0;
  VaccineMilestone? next;
  for (var i = searchFrom; i < milestones.length; i++) {
    if (!milestones[i].allCompleted) {
      next = milestones[i];
      break;
    }
  }

  return EpiVisitSummary(
    overdueCount: overdueVaccineNames.length,
    overdueVaccineNames: overdueVaccineNames,
    currentMilestoneLabel: currentMilestone?.label ?? '',
    nextMilestoneLabel: next?.label,
    nextMilestoneDate: next?.scheduledDate,
    nextMilestoneVaccineNames:
        next?.vaccines.map((v) => v.display).toList() ?? const [],
  );
}
