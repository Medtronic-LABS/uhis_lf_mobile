import '../constants/app_strings.dart';
import '../../features/visit/forms/rmnch_referral_facility.dart';

/// Locale-aware label for a stored referral-facility wire value across RMNCH,
/// EPI, and NCD programmes.
abstract final class ReferralFacilityLabels {
  ReferralFacilityLabels._();

  static String labelOf(String? raw) {
    if (raw == null || raw.trim().isEmpty) return raw ?? '';
    final t = raw.trim();
    for (final o in RmnchReferralFacility.options) {
      if (o.id == t) return RmnchReferralFacility.labelOf(o);
    }
    final epi = EpiStrings.localizeReferralFacility(t);
    if (epi != t) return epi;
    return PatientDetailStrings.ncdFacilityType(t);
  }
}
