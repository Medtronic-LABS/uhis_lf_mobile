import '../../../core/models/programme.dart';
import '../naba/naba_models.dart';
import 'childhood_visit.dart';

/// Builds Spice-shaped assessment `summary` / `otherDetails` patches from
/// Step 3 (visit recommendation) inputs.
///
/// Spice writes these into `AssessmentViewModel.otherAssessmentDetails` on the
/// summary screen and persists them via `updateOtherAssessmentDetails()` before
/// offline-sync. On the wire they become `assessments[].summary` (not inside
/// `assessmentDetails`).
abstract final class VisitSummaryDetails {
  VisitSummaryDetails._();

  /// Spice `yyyy-MM-dd'T'HH:mm:ssZZZZZ` midnight UTC — same as
  /// [ChildhoodVisit.formatNextVisitDate] / [NcdStatus.referredSummary].
  static String formatNextVisitDate(DateTime date) =>
      ChildhoodVisit.formatNextVisitDate(date);

  /// Spice `AssessmentFamilyPlanningSummaryFragment` — no follow-up date row.
  static bool isFamilyPlanningWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'FP' || n == 'FAMILYPLANNING';
  }

  /// Spice `AssessmentPregnantWomenRegistrationSummaryFragment` — no follow-up
  /// date row; `updatePregnantWomanAssessmentDetails()` does not stamp summary.
  static bool isPwProfileWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'PWPROFILE' ||
        n == 'PW' ||
        n == 'PREGNANTWOMENPROFILE' ||
        n == 'PREGNANTWOMENREGISTRATION';
  }

  /// PW registration-only visit — no Step 3 follow-up date (Spice parity).
  static bool isPwRegistrationOnlyVisit({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
  }) {
    final effective = _effectiveProgrammes(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    );
    return effective.length == 1 && effective.contains(Programme.pw);
  }

  static bool isEyeCareWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'EYECARE' || n == 'EYE';
  }

  static bool isCataractWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'CATARACT';
  }

  /// Spice `BDEyeCareAssessmentSummaryFragment` — never stamps nextVisitDate.
  static bool isEyeCareOnlyVisit({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
    Iterable<String>? assessmentTypes,
  }) {
    if (_isEyeCareOnlyFromAssessments(assessmentTypes)) return true;
    final effective = _effectiveProgrammes(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    );
    return effective.length == 1 && effective.contains(Programme.eyeCare);
  }

  static bool _isEyeCareOnlyFromAssessments(Iterable<String>? types) {
    if (types == null) return false;
    final normalized = types
        .map((t) => t.trim().toUpperCase())
        .where((t) => t.isNotEmpty)
        .toSet();
    return normalized.length == 1 && normalized.contains('EYE_CARE');
  }

  /// Cataract-only visit (no combined NCD/ANC/etc. on this encounter).
  static bool isCataractOnlyVisit({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
  }) {
    final effective = _effectiveProgrammes(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    );
    return effective.length == 1 && effective.contains(Programme.cataract);
  }

  /// Spice `AssessmentPregnancyOutcomeSummaryFragment` — no next follow-up row.
  static bool isPregnancyOutcomeWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'PREGNANCYOUTCOME';
  }

  /// RMNCH mother PNC assessment (combined PO+PNC or standalone PNC visit).
  static bool isPncMotherWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    final n = tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '');
    return n == 'PNCMOTHER' || n == 'PNC';
  }

  static bool isAncWireType(String? tag) {
    if (tag == null || tag.isEmpty) return false;
    return tag.toUpperCase().replaceAll('_', '').replaceAll(' ', '') == 'ANC';
  }

  static Set<String> normalizedAssessmentTypes(Iterable<String>? types) {
    if (types == null) return {};
    return types
        .map((t) => t.trim().toUpperCase().replaceAll('_', '').replaceAll(' ', ''))
        .where((t) => t.isNotEmpty)
        .toSet();
  }

  static bool includesPregnancyOutcomeAssessment({
    Iterable<String>? assessmentTypes,
  }) {
    return normalizedAssessmentTypes(assessmentTypes)
        .contains('PREGNANCYOUTCOME');
  }

  static bool includesPncMotherAssessment({
    Iterable<String>? assessmentTypes,
  }) {
    final types = normalizedAssessmentTypes(assessmentTypes);
    return types.contains('PNCMOTHER') || types.contains('PNC');
  }

  /// PO saved without a [PNC_MOTHER] assessment on this encounter — Spice
  /// pregnancy-outcome summary has no follow-up date picker.
  static bool isPregnancyOutcomeOnlyVisit({
    Iterable<String>? assessmentTypes,
  }) {
    if (!includesPregnancyOutcomeAssessment(assessmentTypes: assessmentTypes)) {
      return false;
    }
    return !includesPncMotherAssessment(assessmentTypes: assessmentTypes);
  }

  /// Whether Step 3 should schedule local follow-up / stamp next_due_at.
  ///
  /// Eye care: never (Spice only stamps `referredSite` at submit).
  /// Cataract: only when referred (+5 day wire stamp); not when cleared.
  static bool shouldScheduleStep3FollowUp({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
    required bool isReferred,
    Iterable<String>? assessmentTypes,
  }) {
    if (isPwRegistrationOnlyVisit(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    )) {
      return false;
    }
    if (isEyeCareOnlyVisit(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
      assessmentTypes: assessmentTypes,
    )) {
      return false;
    }
    if (isCataractOnlyVisit(
          programmes: programmes,
          primaryProgramme: primaryProgramme,
        ) &&
        !isReferred) {
      return false;
    }
    if (isPregnancyOutcomeOnlyVisit(assessmentTypes: assessmentTypes)) {
      return false;
    }
    return true;
  }

  /// Resolves the Step 3 follow-up date after programme-aware Spice rules.
  static DateTime? resolveStep3FollowUpDate({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
    required bool isReferred,
    DateTime? skSelected,
    DateTime? firstTimelineDate,
    DateTime? programmeDefault,
    Iterable<String>? assessmentTypes,
  }) {
    if (!shouldScheduleStep3FollowUp(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
      isReferred: isReferred,
      assessmentTypes: assessmentTypes,
    )) {
      return null;
    }
    return skSelected ?? firstTimelineDate ?? programmeDefault;
  }

  static Set<Programme> _effectiveProgrammes({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
  }) {
    if (programmes.isNotEmpty) return programmes;
    if (primaryProgramme != Programme.unknown) return {primaryProgramme};
    return programmes;
  }

  /// Step 3 timeline rows — drop programmes Spice never dates on summary.
  ///
  /// When [programmes] / [primaryProgramme] indicate a visit that never gets a
  /// summary follow-up date (eye-care-only, PW-only, non-referred cataract),
  /// returns an empty list even if NABA sent generic untagged rows.
  static List<NabaFollowUpItem> followUpItemsForSummary(
    List<NabaFollowUpItem> items, {
    Set<Programme> programmes = const {},
    Programme primaryProgramme = Programme.unknown,
    bool isReferred = false,
    Iterable<String>? assessmentTypes,
  }) {
    if (!shouldScheduleStep3FollowUp(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
      isReferred: isReferred,
      assessmentTypes: assessmentTypes,
    )) {
      return const [];
    }
    var filtered = items
        .where(
          (i) =>
              !isFamilyPlanningWireType(i.programme) &&
              !isPwProfileWireType(i.programme) &&
              !isEyeCareWireType(i.programme) &&
              !isCataractWireType(i.programme),
        )
        .toList();
    // PO+PNC: PNC summary dates the next visit — drop ANC rows while the
    // patient may still be ANC-enrolled until postpartum projection lands.
    if (includesPncMotherAssessment(assessmentTypes: assessmentTypes)) {
      filtered = filtered
          .where((i) => !isAncWireType(i.programme))
          .toList(growable: false);
    }
    return filtered;
  }

  /// Rule-based fallback must not invent a generic follow-up on visits Spice
  /// never dates on summary (FP/PW/Eye) or where a programme default applies
  /// (referred Cataract → +5 days, not a generic 4-week row).
  static bool shouldAddGenericFollowUpFallback({
    required Set<Programme> programmes,
    Programme primaryProgramme = Programme.unknown,
    Iterable<String>? assessmentTypes,
  }) {
    if (isPregnancyOutcomeOnlyVisit(assessmentTypes: assessmentTypes)) {
      return false;
    }
    if (isPwRegistrationOnlyVisit(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    )) {
      return false;
    }
    if (isEyeCareOnlyVisit(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    )) {
      return false;
    }
    if (isCataractOnlyVisit(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    )) {
      return false;
    }
    final effective = _effectiveProgrammes(
      programmes: programmes,
      primaryProgramme: primaryProgramme,
    );
    if (effective.length == 1 &&
        effective.contains(Programme.familyPlanning)) {
      return false;
    }
    return true;
  }

  /// Per-assessment-type patch for keys that belong in wire `summary`.
  ///
  /// Returns an empty map when this type gets nothing from Step 3 (e.g. TB has
  /// no nextVisitDate on Spice's TB summary; Eye Care's `referredSite` is
  /// already stamped at form submit).
  static Map<String, dynamic> patchFor({
    required String assessmentType,
    DateTime? nextVisitDate,
    required bool isReferred,
    String? referralFacilityType,
    String? referredSiteId,
  }) {
    final type = assessmentType.toUpperCase();
    final patch = <String, dynamic>{};

    final stampNextVisit = switch (type) {
      // Spice AssessmentRMNCHSummaryFragment — always stamps nextVisitDate.
      'ANC' || 'PNC' || 'PNC_MOTHER' || 'PNC_NEONATE' || 'PNC_CHILD' => true,
      // Spice BD NCD / Cataract summary — only when referred.
      'NCD' || 'CATARACT' => isReferred,
      // Spice ICCM / Other Symptoms — date picker / OnTreatment auto.
      'ICCM' || 'IMCI' || 'OTHER' || 'OTHER_SYMPTOMS' || 'OTHERSYMPTOMS' =>
        true,
      // Childhood age-band date is stamped at form submit; allow SK override
      // when Step 3 shows a picker date.
      'CHILDHOOD_VISIT' => nextVisitDate != null,
      // Spice TB / Eye summary: no nextVisitDate on summary (Eye has referredSite
      // from form submit; TB only referral site).
      'TB' || 'EYE_CARE' || 'CHILD_IMMUNIZATION' => false,
      'PWPROFILE' || 'PREGNANCY_OUTCOME' || 'PREGNANCYOUTCOME' || 'FP' ||
      'FAMILY_PLANNING' =>
        false,
      _ => nextVisitDate != null,
    };

    if (stampNextVisit && nextVisitDate != null) {
      patch['nextVisitDate'] = formatNextVisitDate(nextVisitDate);
    }

    // Referral facility keys — Spice RMNCH / NCD / TB / Eye summary spinners.
    // Eye's `referredSite` (org FHIR) stays from form submit; site id / type
    // from Step 3 still merge when referred.
    if (isReferred) {
      if (referralFacilityType != null && referralFacilityType.isNotEmpty) {
        patch['referralFacilityType'] = referralFacilityType;
      }
      if (referredSiteId != null && referredSiteId.isNotEmpty) {
        patch['referredSiteId'] = referredSiteId;
      }
    }

    return patch;
  }
}
