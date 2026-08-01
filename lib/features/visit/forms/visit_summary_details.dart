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
