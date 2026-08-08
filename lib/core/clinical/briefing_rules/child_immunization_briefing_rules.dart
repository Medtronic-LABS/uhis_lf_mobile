/// Deterministic Child Immunization clinical findings for the "Before You
/// Knock" briefing. Pure function — takes an already-built EPI schedule
/// (`EpiScheduleEngine.build()` output) plus the child's last two weight
/// readings, so it never touches the DB/asset bundle itself.
library;

import '../../../features/visit/immunisation/epi_schedule_engine.dart';
import '../../constants/app_strings.dart';
import 'clinical_finding.dart';

/// The "due within 7 days" window is tighter than `EpiScheduleEngine`'s own
/// `upcoming` classification (≤28 days) — recomputed here from
/// `VaccineEntry.scheduledDate` rather than adding a new status to the
/// shared engine, to keep this rule's window independently adjustable.
const _dueSoonWindowDays = 7;

List<ClinicalFinding> evaluateChildImmunizationFindings({
  required List<VaccineMilestone> milestones,
  double? latestWeightKg,
  double? previousWeightKg,
  DateTime? today,
}) {
  final now = today ?? DateTime.now();
  final allVaccines = milestones.expand((m) => m.vaccines).toList();

  final findings = <ClinicalFinding>[];

  // ── Overdue doses ──
  final overdue = allVaccines
      .where((v) => v.isOverdue || v.status == VaccineStatus.dueNow)
      .toList();
  if (overdue.isNotEmpty) {
    final names = overdue.map((v) => v.display).join(', ');
    findings.add(ClinicalFinding(
      code: 'childImmunization.overdue',
      message: ClinicalFindingStrings.childImmunizationOverdueDoses(overdue.length, names),
      programme: 'childImmunization',
    ));
  }

  // ── Weight gain slowed (2-point delta, documented approximation) ──
  // No numeric cutoff was specified in the rule table — this uses the
  // simplest literal reading (latest reading no higher than the previous
  // one) rather than inventing a clinically-validated threshold. Flag for
  // review once a real cutoff is defined.
  final weightGainSlowed = latestWeightKg != null &&
      previousWeightKg != null &&
      latestWeightKg <= previousWeightKg;
  if (weightGainSlowed) {
    findings.add(ClinicalFinding(
      code: 'childImmunization.weightGainSlowed',
      message: ClinicalFindingStrings.childImmunizationWeightGainSlowed,
      programme: 'childImmunization',
    ));
  }

  // ── Dose due within next 7 days (not yet overdue) ──
  final dueSoon = allVaccines.where((v) {
    if (v.status != VaccineStatus.upcoming) return false;
    final daysDiff = v.scheduledDate.difference(now).inDays;
    return daysDiff > 0 && daysDiff <= _dueSoonWindowDays;
  });
  for (final v in dueSoon) {
    findings.add(ClinicalFinding(
      code: 'childImmunization.dueSoon',
      message: ClinicalFindingStrings.childImmunizationDueSoon(v.display),
      programme: 'childImmunization',
    ));
  }

  // ── Fallback ──
  if (findings.isEmpty) {
    findings.add(ClinicalFinding(
      code: 'childImmunization.onSchedule',
      message: ClinicalFindingStrings.childImmunizationOnSchedule,
      programme: 'childImmunization',
    ));
  }

  return findings;
}
