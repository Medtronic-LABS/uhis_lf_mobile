// Programme-smart badge label — shared by the dashboard worklist and the
// Patients / household list. Display follows **strict latest service** when
// [latestServiceKind] is known; otherwise enrolment-only fallbacks.

import '../constants/app_strings.dart';
import '../models/programme.dart';
import 'latest_service_badge.dart';

/// `Programme.wireTag`-family kinds counted as completed ANC / PNC visits.
const List<String> ancVisitKinds = ['ANC', 'PREGNANCY', 'PREGNANT', 'EMTCT'];
const List<String> pncVisitKinds = ['PNC', 'POSTNATAL'];

/// Local-assessment `assessment_type` values for PNC visits — the unified
/// form writes `PNC_MOTHER`; synced history uses the [pncVisitKinds] tags.
const List<String> pncLocalVisitKinds = [
  ...pncVisitKinds,
  'PNC_MOTHER',
  'PNCMOTHER',
];

/// Synced/local assessment kinds for a registered pregnancy outcome form.
const List<String> pregnancyOutcomeVisitKinds = [
  'PREGNANCY_OUTCOME',
  'PREGNANCYOUTCOME',
];

/// Completed Family Planning service visits (synced + local assessment types).
const List<String> familyPlanningVisitKinds = [
  'FAMILY_PLANNING',
  'FAMILYPLANNING',
];

/// Shared reason string + programme key for badge styling.
({String reason, Programme badgeProgramme}) patientBadgeLabel({
  String? latestServiceKind,
  required Set<Programme> programmes,
  int ancVisitCount = 0,
  int pncVisitCount = 0,
}) {
  final latest = latestServiceKind?.trim();
  if (latest != null && latest.isNotEmpty) {
    return badgeFromLatestServiceKind(
      latest,
      ancVisitCount: ancVisitCount,
      pncVisitCount: pncVisitCount,
    );
  }

  if (programmes.isNotEmpty) {
    return (
      reason: MissionDashboardStrings.enrolled,
      badgeProgramme: primaryProgrammeOf(programmes),
    );
  }
  return (
    reason: MissionDashboardStrings.newVisit,
    badgeProgramme: Programme.unknown,
  );
}

/// Picks the one programme to key a badge off of, by clinical priority.
Programme primaryProgrammeOf(Set<Programme> programmes) {
  if (programmes.contains(Programme.imci)) return Programme.imci;
  if (programmes.contains(Programme.anc)) return Programme.anc;
  if (programmes.contains(Programme.pnc)) return Programme.pnc;
  if (programmes.contains(Programme.ncd)) return Programme.ncd;
  if (programmes.contains(Programme.tb)) return Programme.tb;
  return programmes.isNotEmpty ? programmes.first : Programme.unknown;
}

/// Legacy programme-set label (tests / fallback). Prefer [patientBadgeLabel]
/// with [latestServiceKind] for UI.
String programmeReason({
  required Set<Programme> programmes,
  int ancVisitCount = 0,
  int pncVisitCount = 0,
}) {
  if (programmes.contains(Programme.anc)) {
    return ancVisitCount > 0
        ? '${MissionDashboardStrings.ancVisitLabel} ${ancVisitCount + 1} '
            '${MissionDashboardStrings.dueSuffix}'
        : MissionDashboardStrings.enrolled;
  }
  if (programmes.contains(Programme.pnc)) {
    return pncVisitCount > 0
        ? '${MissionDashboardStrings.pncVisitLabel} ${pncVisitCount + 1} '
            '${MissionDashboardStrings.dueSuffixTitleCase}'
        : MissionDashboardStrings.enrolled;
  }
  if (programmes.contains(Programme.imci) || programmes.contains(Programme.epi)) {
    return MissionDashboardStrings.childImmunisation;
  }
  if (programmes.contains(Programme.ncd)) return MissionDashboardStrings.ncdCheckup;
  if (programmes.contains(Programme.tb)) return MissionDashboardStrings.tbCheck;
  return MissionDashboardStrings.newVisit;
}
