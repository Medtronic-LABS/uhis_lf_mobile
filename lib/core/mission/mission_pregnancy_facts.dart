/// Per-patient pregnancy / postpartum snapshot derived from the bundle's
/// `pregnancyInfos[]` array during offline sync. Read by
/// `MissionDashboardService._classify` to fire CRITICAL drivers
/// (`pnc-window`, `anc-near-term`, `delivery-complication`, `pnc-illness`,
/// `hi-risk-anc-gap`).
///
/// Spec: leapfrog-setup/designs/dashboard-prioritization-impl.md
/// (Medical refinements table).
library;

/// Immutable snapshot of a single patient's pregnancy / postpartum state.
/// All fields default `false` so callers can construct partial snapshots
/// without enumerating every flag.
class PregnancyFacts {
  const PregnancyFacts({
    this.highRiskPregnantWoman = false,
    this.hasGapsInAnc = false,
    this.isPostpartumWindow = false,
    this.isNearTermAnc = false,
    this.hadDeliveryComplications = false,
    this.hasPncIllness = false,
  });

  /// `pregnancyInfos[].highRiskPregnantWoman == true` OR `highRiskMother == true`.
  final bool highRiskPregnantWoman;

  /// `pregnancyInfos[].gapsInAnc` non-empty / non-null.
  final bool hasGapsInAnc;

  /// `pregnancyInfos[].dateOfDelivery` within last 42 days (WHO PNC window).
  final bool isPostpartumWindow;

  /// `pregnancyInfos[].estimatedDeliveryDate` within next 14 days.
  final bool isNearTermAnc;

  /// `complicationsDuringDelivery` non-null OR `isDeliveryAtHome == true`.
  final bool hadDeliveryComplications;

  /// `pncIllness` non-null.
  final bool hasPncIllness;

  /// True if any solo flag fires a CRITICAL driver. Combined hi-risk + ANC-gap
  /// is still evaluated by the classifier, not here.
  bool get firesAnySoloCritical =>
      isPostpartumWindow ||
      isNearTermAnc ||
      hadDeliveryComplications ||
      hasPncIllness;

  /// Sentinel empty snapshot — used when no pregnancyInfos row exists for
  /// the patient. Lets call sites read `pregnancyByPatientId[pid] ?? empty`
  /// without nulls.
  static const PregnancyFacts empty = PregnancyFacts();
}
