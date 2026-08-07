/// When PNC mother Hb / blood-sugar fields become mandatory — ported from
/// Android `AssessmentRMNCHFragment.managePncFormBasedOnPregnancyDetail`.
library;

/// History / cohort inputs that are stable for the visit (not live form taps).
class PncMandatoryHistory {
  const PncMandatoryHistory({
    this.pncVisitNumber = 1,
    this.ancVisitCount = 0,
    this.hadAnemiaDuringPregnancy = false,
    this.priorPncAnemiaLevel,
    this.priorPncHighBloodSugar = false,
    this.knownDmOrGdmFromHistory = false,
  });

  /// 1-based current PNC visit (`pncVisitNo + 1`). `0` = history not loaded.
  final int pncVisitNumber;

  /// Completed ANC visits on the pregnancy episode (`ancVisitNo`).
  final int ancVisitCount;

  /// ANC high-risk / Hb indicated anemia during pregnancy.
  final bool hadAnemiaDuringPregnancy;

  /// Prior `pncIllness.anemia` token: `None` / `Mild` / `Moderate` / `Severe`.
  final String? priorPncAnemiaLevel;

  /// Prior `pncIllness.bloodSugar == true`.
  final bool priorPncHighBloodSugar;

  /// DM/GDM known from snapshot illness list or prior PNC illness.
  final bool knownDmOrGdmFromHistory;

  bool get isLoaded => pncVisitNumber > 0;

  /// Unloaded sentinel — only live form signals apply until history is ready.
  static const empty = PncMandatoryHistory(pncVisitNumber: 0);
}

/// Live form answers consulted at validation time.
class PncMandatoryFormSignals {
  const PncMandatoryFormSignals({
    this.heavyBleedingDangerSign = false,
    this.excessiveBleedingAtDelivery = false,
    this.knownDmOrGdmOnForm = false,
  });

  final bool heavyBleedingDangerSign;
  final bool excessiveBleedingAtDelivery;
  final bool knownDmOrGdmOnForm;
}

abstract final class PncMandatoryRules {
  PncMandatoryRules._();

  static bool hemoglobinRequired({
    required PncMandatoryHistory history,
    required PncMandatoryFormSignals form,
  }) {
    if (form.heavyBleedingDangerSign || form.excessiveBleedingAtDelivery) {
      return true;
    }
    if (!history.isLoaded) return false;

    if (history.pncVisitNumber <= 1) {
      // First SK PNC with no prior ANC → always measure Hb.
      if (history.ancVisitCount < 1) return true;
      // First PNC after ANC with anemia in pregnancy.
      if (history.hadAnemiaDuringPregnancy) return true;
      return false;
    }

    // Visit 2+: prior moderate/severe anemia.
    final level = history.priorPncAnemiaLevel?.trim().toLowerCase() ?? '';
    return level == 'moderate' || level == 'severe';
  }

  static bool bloodSugarRequired({
    required PncMandatoryHistory history,
    required PncMandatoryFormSignals form,
  }) {
    if (form.knownDmOrGdmOnForm) return true;
    if (!history.isLoaded) return false;
    if (history.knownDmOrGdmFromHistory) return true;

    if (history.pncVisitNumber <= 1) {
      // First SK PNC with no prior ANC → always measure glucose.
      return history.ancVisitCount < 1;
    }

    // Visit 2+: prior high blood sugar on pncIllness.
    return history.priorPncHighBloodSugar;
  }
}
