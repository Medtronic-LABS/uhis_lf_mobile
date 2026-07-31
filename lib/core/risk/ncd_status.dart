import '../clinical/assessment_thresholds.dart';

/// NCD `encounter.customStatus` tokens + referred-reason / facility-type wire
/// strings, ported from Android SPICE `AssessmentStatusGenerator` (NCD branch),
/// `ReferredReason`, and `ReferralResultGenerator`.
abstract final class NcdStatus {
  NcdStatus._();

  static const String normalNcd = 'NORMAL_NCD';
  static const String uncontrolledBp = 'UNCONTROLLED_BP';
  static const String uncontrolledBg = 'UNCONTROLLED_BG';

  /// Spice `ReferredReason` wire values for BD community NCD.
  static const String reasonHighBp = 'High BP';
  static const String reasonHighBg = 'High BG';
  static const String reasonSymptoms = 'Symptoms';

  /// Spice `AssessmentDefinedParams.FACILITY_TYPE_*`.
  static const String facilityCommunityClinic = 'Community Clinic';
  static const String facilityUpazila = 'Upazila Health Complex';

  /// Builds the NCD customStatus list from referral outcome.
  ///
  /// Spice rules:
  /// - `UNCONTROLLED_BP` / `UNCONTROLLED_BG` when referral reasons contain
  ///   High BP / High BG
  /// - `NORMAL_NCD` only when the visit is **not** referred and neither
  ///   uncontrolled token was added
  static List<String> status({
    required bool isReferred,
    required List<String> referredReasons,
  }) {
    final out = <String>[];
    if (referredReasons.contains(reasonHighBp)) {
      out.add(uncontrolledBp);
    }
    if (referredReasons.contains(reasonHighBg)) {
      out.add(uncontrolledBg);
    }
    if (!isReferred &&
        !out.contains(uncontrolledBp) &&
        !out.contains(uncontrolledBg)) {
      out.add(normalNcd);
    }
    return out;
  }

  /// Spice `resolveReferralFacilityType` for BD community NCD.
  ///
  /// Follow-up referrals always go to Upazila. First-visit referrals go to
  /// Upazila when BP ≥ 160/100 or glucose > 15 mmol/L; otherwise Community Clinic.
  static String resolveFacilityType({
    required bool isFollowUpVisit,
    required List<String> referredReasons,
    int? avgSystolic,
    int? avgDiastolic,
    double? glucoseMmol,
  }) {
    if (isFollowUpVisit) return facilityUpazila;
    final hasBpOrBg = referredReasons.contains(reasonHighBp) ||
        referredReasons.contains(reasonHighBg);
    if (!hasBpOrBg) return facilityCommunityClinic;
    final bpUpazila = (avgSystolic != null && avgSystolic >= 160) ||
        (avgDiastolic != null && avgDiastolic >= 100);
    final bgUpazila =
        glucoseMmol != null && glucoseMmol > ncdUpazilaGlucoseMmol;
    return (bpUpazila || bgUpazila) ? facilityUpazila : facilityCommunityClinic;
  }

  /// Top-level sync `summary` for a referred NCD assessment.
  static Map<String, dynamic> referredSummary({
    required String referralFacilityType,
    String? referredSiteId,
    DateTime? now,
  }) {
    final base = now?.toUtc() ?? DateTime.now().toUtc();
    final due = DateTime.utc(base.year, base.month, base.day)
        .add(const Duration(days: 5));
    // Spice: yyyy-MM-dd'T'HH:mm:ssZZZZZ with inUTC=true → +00:00 midnight.
    final nextVisitDate =
        '${due.year.toString().padLeft(4, '0')}-'
        '${due.month.toString().padLeft(2, '0')}-'
        '${due.day.toString().padLeft(2, '0')}T00:00:00+00:00';
    return {
      'nextVisitDate': nextVisitDate,
      'referralFacilityType': referralFacilityType,
      if (referredSiteId != null &&
          referredSiteId.isNotEmpty &&
          referralFacilityType == facilityCommunityClinic)
        'referredSiteId': referredSiteId,
    };
  }
}
