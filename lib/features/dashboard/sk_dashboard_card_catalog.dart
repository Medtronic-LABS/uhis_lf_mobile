import '../../core/constants/app_strings.dart';
import '../../core/db/spice_dashboard_dao.dart';
import 'sk_dashboard_gating.dart';

/// One KPI tile — title + count (Spice `DashboardCardItem` without navigation).
typedef SkDashboardCard = ({String title, int count});

/// Row in the services list — section heading or KPI card.
typedef SkDashboardListEntry = ({bool isHeader, String title, int? count});

/// Service programme sub-tabs under Spice **Services**.
enum SkDashboardServicesCategory {
  all,
  rmnch,
  cd,
  ncd,
  eye,
  cataract,
}

/// Card order and gating aligned with Spice `DashboardFragment.showView`.
abstract final class SkDashboardCardCatalog {
  static List<SkDashboardServicesCategory> programmeCategories(
    SkDashboardGating gating,
  ) {
    return [
      SkDashboardServicesCategory.rmnch,
      SkDashboardServicesCategory.cd,
      if (gating.showNcd) SkDashboardServicesCategory.ncd,
      if (gating.showEyeCare) SkDashboardServicesCategory.eye,
      if (gating.showCataract) SkDashboardServicesCategory.cataract,
    ];
  }

  /// Chips: **All** first, then each programme (Spice services filter).
  static List<SkDashboardServicesCategory> serviceSubTabs(
    SkDashboardGating gating,
  ) {
    return [
      SkDashboardServicesCategory.all,
      ...programmeCategories(gating),
    ];
  }

  static String labelFor(SkDashboardServicesCategory category) {
    switch (category) {
      case SkDashboardServicesCategory.all:
        return PerformanceStrings.dashboardSubTabAll;
      case SkDashboardServicesCategory.rmnch:
        return PerformanceStrings.dashboardSubTabRmnch;
      case SkDashboardServicesCategory.cd:
        return PerformanceStrings.dashboardSubTabCd;
      case SkDashboardServicesCategory.ncd:
        return PerformanceStrings.dashboardSubTabNcd;
      case SkDashboardServicesCategory.eye:
        return PerformanceStrings.dashboardSubTabEye;
      case SkDashboardServicesCategory.cataract:
        return PerformanceStrings.dashboardSubTabCataract;
    }
  }

  static List<SkDashboardCard> cardsForServiceCategory(
    SkDashboardServicesCategory category,
    SpiceDashboardCounts c,
    SkDashboardGating gating,
  ) {
    switch (category) {
      case SkDashboardServicesCategory.all:
        return const [];
      case SkDashboardServicesCategory.rmnch:
        return rmnch(c);
      case SkDashboardServicesCategory.cd:
        return cd(c);
      case SkDashboardServicesCategory.ncd:
        return gating.showNcd ? ncd(c) : const [];
      case SkDashboardServicesCategory.eye:
        return gating.showEyeCare ? eyeCare(c) : const [];
      case SkDashboardServicesCategory.cataract:
        return gating.showCataract ? cataract(c) : const [];
    }
  }

  /// **All** tab — KPIs grouped under programme headings (RMNCH, CD, …).
  static List<SkDashboardListEntry> allServicesGrouped(
    SpiceDashboardCounts c,
    SkDashboardGating gating,
  ) {
    final entries = <SkDashboardListEntry>[];
    for (final category in programmeCategories(gating)) {
      final cards = cardsForServiceCategory(category, c, gating);
      if (cards.isEmpty) continue;
      entries.add((isHeader: true, title: labelFor(category), count: null));
      for (final card in cards) {
        entries.add((isHeader: false, title: card.title, count: card.count));
      }
    }
    return entries;
  }

  /// RMNCH through family planning (Spice block before CD / clinical workflows).
  static List<SkDashboardCard> rmnch(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiPwRegistration, count: c.pregnantWomenRegistrationCount),
      (title: PerformanceStrings.kpiAnc, count: c.ancCount),
      (title: PerformanceStrings.kpiPw4MonthAnc, count: c.pwIdentifiedFirst4MonthsWithAncCount),
      (title: PerformanceStrings.kpiAnc3Plus, count: c.anc3PlusCount),
      (title: PerformanceStrings.kpiPregnancyOutcome, count: c.pregnancyOutcomeCount),
      (title: PerformanceStrings.kpiHighRiskPw, count: c.highRiskPregnantWomenCount),
      (title: PerformanceStrings.kpiChildVisit, count: c.childVisitCount),
      (title: PerformanceStrings.kpiHouseholdRegistered, count: c.householdRegisteredCount),
      (title: PerformanceStrings.kpiFamilyPlanning, count: c.familyPlanningCount),
    ];
  }

  /// Communicable diseases (`dashboard_cd_services` / `CARD_OTHER_SERVICES`).
  static List<SkDashboardCard> cd(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiOtherServices, count: c.otherServicesCount),
    ];
  }

  static List<SkDashboardCard> ncd(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiNcdScreening, count: c.ncdScreeningFirstServiceCount),
      (title: PerformanceStrings.kpiNcdReferred, count: c.ncdFollowUpReferralCount),
      (title: PerformanceStrings.kpiNcdFollowUp, count: c.ncdFollowUpAssessmentCount),
      (title: PerformanceStrings.kpiTotalNcd, count: c.totalNcdServicesCount),
      (title: PerformanceStrings.kpiLinkedToCare, count: c.linkedToCareCount),
    ];
  }

  static List<SkDashboardCard> eyeCare(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiEyeScreening, count: c.eyeCareCount),
      (title: PerformanceStrings.kpiGlassesSold, count: c.glassesSoldCustomStatusCount),
    ];
  }

  static List<SkDashboardCard> cataract(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiCataract, count: c.cataractCount),
      (title: PerformanceStrings.kpiNcdInCataractCamp, count: c.ncdServicesInCataractCampCount),
      (title: PerformanceStrings.kpiReferredOperation, count: c.patientsReferredForOperationCount),
    ];
  }

  /// Spice `DashboardTab.DEMOGRAPHIC` — three registration totals.
  static List<SkDashboardCard> demographic(SpiceDashboardCounts c) {
    return [
      (title: PerformanceStrings.kpiTotalHousehold, count: c.householdRegisteredCount),
      (title: PerformanceStrings.kpiTotalMember, count: c.memberRegisteredCount),
      (
        title: PerformanceStrings.kpiTotalPregnantWomen,
        count: c.pregnantWomenRegistrationCount,
      ),
    ];
  }
}
