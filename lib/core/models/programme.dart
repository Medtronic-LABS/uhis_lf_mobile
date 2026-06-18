/// The four UHIS frontline health programmes surfaced by the AI Worklist.
///
/// The wire-side `diagnosisType[]` field (spice-service `PatientDTO`) and the
/// per-domain detail endpoints (`/medical-review/tb/details`, `/pregnancy/info`,
/// `/immunisation/list`, etc.) carry programme membership in different shapes;
/// [Programme.fromTag] is the single home for the mapping.
enum Programme {
  imci,
  anc,
  pnc,
  ncd,
  tb,
  epi,
  nutrition,
  familyPlanning,
  cataract,
  eyeCare,
  unknown;

  /// Case-insensitive tag mapper. Accepts the strings the spice service
  /// returns in `diagnosisType[]`, on enrolment markers, and on follow-up rows.
  static Programme? fromTag(String? tag) {
    if (tag == null) return null;
    final t = tag.trim().toUpperCase();
    if (t.isEmpty) return null;
    switch (t) {
      case 'IMCI':
      case 'ICCM':
      case 'IMCI_GENERAL':
      case 'ICCM_UNDER_5':
      case 'ICCM_UNDER_2':
      case 'UNDER_5':
        return Programme.imci;
      case 'ANC':
      case 'PREGNANCY':
      case 'PREGNANT':
      case 'EMTCT':
        return Programme.anc;
      case 'PNC':
      case 'POSTNATAL':
        return Programme.pnc;
      case 'NCD':
      case 'HYPERTENSION':
      case 'HTN':
      case 'DIABETES':
      case 'DM':
      case 'DIABETES_MELLITUS':
      case 'CVD':
        return Programme.ncd;
      case 'TB':
      case 'TUBERCULOSIS':
      case 'PRESUMPTIVE_TB':
        return Programme.tb;
      case 'EPI':
      case 'IMMUNIZATION':
      case 'IMMUNISATION':
        return Programme.epi;
      case 'NUTRITION':
      case 'SAM':
      case 'MAM':
      case 'MALNUTRITION':
        return Programme.nutrition;
      case 'FAMILY_PLANNING':
      case 'FP':
      case 'FAMILYPLANNING':
        return Programme.familyPlanning;
      case 'CATARACT':
      case 'EYE_CATARACT':
        return Programme.cataract;
      case 'EYE_CARE':
      case 'EYE':
      case 'EYECARE':
        return Programme.eyeCare;
    }
    return null;
  }

  /// Canonical wire tag — used when persisting and when re-emitting to the
  /// server. Stable across the column `patient_programmes.programme`.
  String get wireTag {
    switch (this) {
      case Programme.imci:
        return 'IMCI';
      case Programme.anc:
        return 'ANC';
      case Programme.pnc:
        return 'PNC';
      case Programme.ncd:
        return 'NCD';
      case Programme.tb:
        return 'TB';
      case Programme.epi:
        return 'EPI';
      case Programme.nutrition:
        return 'NUTRITION';
      case Programme.familyPlanning:
        return 'FAMILY_PLANNING';
      case Programme.cataract:
        return 'CATARACT';
      case Programme.eyeCare:
        return 'EYE_CARE';
      case Programme.unknown:
        return 'UNKNOWN';
    }
  }

  static Programme? fromWireTag(String? tag) {
    if (tag == null) return null;
    switch (tag.toUpperCase()) {
      case 'IMCI':
        return Programme.imci;
      case 'ANC':
        return Programme.anc;
      case 'PNC':
        return Programme.pnc;
      case 'NCD':
        return Programme.ncd;
      case 'TB':
        return Programme.tb;
      case 'EPI':
        return Programme.epi;
      case 'NUTRITION':
        return Programme.nutrition;
      case 'FAMILY_PLANNING':
        return Programme.familyPlanning;
      case 'CATARACT':
        return Programme.cataract;
      case 'EYE_CARE':
        return Programme.eyeCare;
    }
    return null;
  }

  /// Parse from any string, returning [Programme.unknown] if not recognized.
  static Programme fromString(String? s) {
    if (s == null || s.isEmpty) return Programme.unknown;
    final tag = s.trim().toUpperCase();
    
    // Try fromTag first (handles many variations)
    final fromTagResult = fromTag(tag);
    if (fromTagResult != null) return fromTagResult;
    
    // Direct enum name match
    for (final p in Programme.values) {
      if (p.name.toUpperCase() == tag) return p;
    }
    
    return Programme.unknown;
  }
}
