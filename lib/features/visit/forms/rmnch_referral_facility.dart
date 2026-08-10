import '../../../core/constants/app_strings.dart';
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
  /// UI labels resolve via [labelOf] → `VisitFlow.rmnchReferralFacility.*`
  /// translations so Step 3 follows the app language (not English-only).
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
  ///
  /// Uses the full visit programme set when available so a combined PW+ANC
  /// visit still shows the spinner (primary may be [Programme.pw]). Falls
  /// back to [programme] for callers that only pass the primary pathway.
  static bool showOnStep3({
    required Programme programme,
    required bool isReferred,
    Set<Programme> visitProgrammes = const {},
  }) {
    if (!isReferred) return false;
    if (visitProgrammes.contains(Programme.anc) ||
        visitProgrammes.contains(Programme.pnc)) {
      return true;
    }
    return programme == Programme.anc || programme == Programme.pnc;
  }

  /// Locale-aware label for a spinner row (Bangla when the app language is bn).
  ///
  /// Prefers `strings.json` so Step 3 matches other VisitFlow copy; falls back
  /// to [FieldOption.displayName] (cultureValue / English name).
  static String labelOf(FieldOption option) => getTranslatedString(
        'VisitFlow.rmnchReferralFacility.${option.id}',
        option.displayName,
      );

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
