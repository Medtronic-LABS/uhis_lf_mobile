import '../../core/constants/app_strings.dart';
import '../../core/db/spice_dashboard_dao.dart';
import 'sk_dashboard_gating.dart';

/// One KPI tile — title + count (Spice `DashboardCardItem` without navigation).
typedef SkDashboardCard = ({String title, int count});

/// Card order and gating aligned with Spice `DashboardFragment.showView`.
abstract final class SkDashboardCardCatalog {
  /// Single SK dashboard list (Spice default view): RMNCH, then NCD, eye, cataract (gated).
  static List<SkDashboardCard> services(
    SpiceDashboardCounts c,
    SkDashboardGating gating,
  ) {
    final cards = <SkDashboardCard>[
      (title: PerformanceStrings.kpiPwRegistration, count: c.pregnantWomenRegistrationCount),
      (title: PerformanceStrings.kpiAnc, count: c.ancCount),
      (title: PerformanceStrings.kpiPw4MonthAnc, count: c.pwIdentifiedFirst4MonthsWithAncCount),
      (title: PerformanceStrings.kpiAnc3Plus, count: c.anc3PlusCount),
      (title: PerformanceStrings.kpiPregnancyOutcome, count: c.pregnancyOutcomeCount),
      (title: PerformanceStrings.kpiPnc, count: c.pncCount),
      (title: PerformanceStrings.kpiHighRiskPw, count: c.highRiskPregnantWomenCount),
      (title: PerformanceStrings.kpiChildVisit, count: c.childVisitCount),
      (title: PerformanceStrings.kpiHouseholdRegistered, count: c.householdRegisteredCount),
      (title: PerformanceStrings.kpiFamilyPlanning, count: c.familyPlanningCount),
    ];

    if (gating.showNcd) {
      cards.addAll([
        (title: PerformanceStrings.kpiNcdScreening, count: c.ncdScreeningFirstServiceCount),
        (title: PerformanceStrings.kpiNcdReferred, count: c.ncdFollowUpReferralCount),
        (title: PerformanceStrings.kpiNcdFollowUp, count: c.ncdFollowUpAssessmentCount),
        (title: PerformanceStrings.kpiTotalNcd, count: c.totalNcdServicesCount),
        (title: PerformanceStrings.kpiLinkedToCare, count: c.linkedToCareCount),
      ]);
    }
    if (gating.showEyeCare) {
      cards.addAll([
        (title: PerformanceStrings.kpiEyeScreening, count: c.eyeCareCount),
        (title: PerformanceStrings.kpiGlassesSold, count: c.glassesSoldCustomStatusCount),
      ]);
    }
    if (gating.showCataract) {
      cards.addAll([
        (title: PerformanceStrings.kpiCataract, count: c.cataractCount),
        (title: PerformanceStrings.kpiNcdInCataractCamp, count: c.ncdServicesInCataractCampCount),
        (title: PerformanceStrings.kpiReferredOperation, count: c.patientsReferredForOperationCount),
      ]);
    }

    return cards;
  }
}
