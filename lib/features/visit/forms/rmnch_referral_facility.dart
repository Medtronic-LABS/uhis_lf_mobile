import '../../../core/models/programme.dart';
import 'form_config.dart';

/// Spice ANC/PNC summary referral-facility spinner options
/// (`rmnch_anc_visit.json` / `rmnch_pnc_visit.json` `referralFacility`).
///
/// On Done, Spice writes the selected option **id** into
/// `summary.referralFacilityType` (via `ReferredPHUSiteID` → type remap).
abstract final class RmnchReferralFacility {
  RmnchReferralFacility._();

  /// Same ids / names / Bangla labels as the Spice form JSON.
  static const List<FieldOption> options = [
    FieldOption(
      id: 'uhfwc',
      name: 'UHFWC (Union health and family welfare center)',
      cultureValue: 'ইউনিয়ন স্বাস্থ্য ও পরিবার কল্যাণ কেন্দ্র',
    ),
    FieldOption(
      id: 'mcwc',
      name: 'MCWC (Mother and Child Welfare Center)',
      cultureValue: 'মাতৃ ও শিশু কল্যাণ কেন্দ্র',
    ),
    FieldOption(
      id: 'uhc',
      name: 'UHC (Upazila Health complex)',
      cultureValue: 'উপজেলা স্বাস্থ্য কমপ্লেক্স',
    ),
    FieldOption(
      id: 'districtHospital',
      name: 'District Hospital',
      cultureValue: 'জেলা সদর হাসপাতাল',
    ),
    FieldOption(
      id: 'medicalCollegeHospital',
      name: 'Medical College Hospital',
      cultureValue: 'মেডিকেল কলেজ হাসপাতাল',
    ),
  ];

  /// Whether Step 3 should show the Spice RMNCH facility spinner.
  static bool showOnStep3({
    required Programme programme,
    required bool isReferred,
  }) =>
      isReferred &&
      (programme == Programme.anc || programme == Programme.pnc);

  /// Locale-aware label for a spinner row.
  static String labelOf(FieldOption option) => option.displayName;

  /// Spice spinner default: first option. Prefer [preferredId] when it is a
  /// known option (e.g. a stale Step 2 value).
  static String initialSelection({String? preferredId}) {
    if (preferredId != null && preferredId.isNotEmpty) {
      for (final o in options) {
        if (o.id == preferredId) return o.id;
      }
    }
    return options.first.id;
  }

  /// Spice Done fallback when nothing was selected.
  static const String unsetWireValue = '-1';
}
