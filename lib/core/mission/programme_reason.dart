// Programme-smart, visit-count-aware badge label — the single shared source
// for "what is this patient's active programme status" (v13 design). Used
// by the dashboard worklist (`MissionDashboardService`) and the Patients/
// household list (`HouseholdListScreen`) so the two surfaces can never drift
// from each other again — this logic previously existed as two separate,
// hand-duplicated copies that had already fallen out of sync.
//
// Pure Dart, no Flutter import — mirrors the "no Flutter binding" rule of
// `mission_dashboard_service.dart`, which is the other caller. Badge
// *colors* (which need `Color`) live in `programmeBadgeColors()` in
// `lib/features/visit/widgets/mission_queue_card.dart` instead.

import '../constants/app_strings.dart';
import '../models/programme.dart';

/// `Programme.wireTag`-family kinds counted as completed ANC / PNC visits.
const List<String> ancVisitKinds = ['ANC', 'PREGNANCY', 'PREGNANT', 'EMTCT'];
const List<String> pncVisitKinds = ['PNC', 'POSTNATAL'];

/// Picks the one programme to key a badge off of, by clinical priority.
Programme primaryProgrammeOf(Set<Programme> programmes) {
  if (programmes.contains(Programme.imci)) return Programme.imci;
  if (programmes.contains(Programme.anc)) return Programme.anc;
  if (programmes.contains(Programme.pnc)) return Programme.pnc;
  if (programmes.contains(Programme.ncd)) return Programme.ncd;
  if (programmes.contains(Programme.tb)) return Programme.tb;
  return programmes.isNotEmpty ? programmes.first : Programme.unknown;
}

/// Visit-count-aware badge label, e.g. "ANC Visit 3 due", "Enrolled",
/// "NCD checkup". Replaces the raw risk-driver reason text with an
/// actionable label (v13 design).
String programmeReason({
  required Set<Programme> programmes,
  int ancVisitCount = 0,
  int pncVisitCount = 0,
}) {
  if (programmes.contains(Programme.anc)) {
    return ancVisitCount > 0
        ? '${MissionDashboardStrings.ancVisitLabel} ${ancVisitCount + 1} due'
        : MissionDashboardStrings.enrolled;
  }
  if (programmes.contains(Programme.pnc)) {
    return pncVisitCount > 0
        ? '${MissionDashboardStrings.pncVisitLabel} ${pncVisitCount + 1} Due'
        : MissionDashboardStrings.enrolled;
  }
  if (programmes.contains(Programme.imci) || programmes.contains(Programme.epi)) {
    return MissionDashboardStrings.childImmunisation;
  }
  if (programmes.contains(Programme.ncd)) return MissionDashboardStrings.ncdCheckup;
  if (programmes.contains(Programme.tb)) return MissionDashboardStrings.tbCheck;
  return MissionDashboardStrings.newVisit;
}
