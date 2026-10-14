import '../constants/app_strings.dart';
import '../models/dashboard_tier.dart';
import '../models/mission_queue_item.dart';
import '../models/programme.dart';

/// Programmes that can show calendar urgency on the home queue (Overdue / Today /
/// This week). IMCI, EPI, TB, FP, PW, pregnancy outcome, etc. do not.
const missionScheduleUrgencyProgrammes = <Programme>{
  Programme.anc,
  Programme.pnc,
  Programme.ncd,
};

/// Uses the **service badge** on the card ([MissionQueueItem.reason] +
/// [MissionQueueItem.badgePrimaryProgramme]), not [MissionQueueItem.programmes].
/// Enrolment can still list ANC while the latest service is PW registration or
/// pregnancy outcome — those must not show Overdue / This week.
bool missionItemSupportsScheduleUrgency(MissionQueueItem item) {
  final badge = item.badgePrimaryProgramme;
  if (!missionScheduleUrgencyProgrammes.contains(badge)) {
    return false;
  }

  final reason = item.reason.trim();
  if (reason == MissionDashboardStrings.pregnancyOutcomeBadge ||
      reason == PatientProfileStrings.pregnancyRegistered) {
    return false;
  }
  if (reason == MissionDashboardStrings.enrolled ||
      reason == MissionDashboardStrings.newVisit) {
    return false;
  }

  switch (badge) {
    case Programme.ncd:
      return reason == MissionDashboardStrings.ncdCheckup;
    case Programme.anc:
      return reason.contains(MissionDashboardStrings.ancVisitLabel);
    case Programme.pnc:
      return reason.contains(MissionDashboardStrings.pncVisitLabel);
    default:
      return false;
  }
}

/// Calendar tier for the status pill on home / member rows.
DashboardTier missionScheduleTierForDisplay(MissionQueueItem item) {
  if (!missionItemSupportsScheduleUrgency(item)) {
    return DashboardTier.upcoming;
  }
  return DashboardTier.fromDueAt(item.dueAt);
}
