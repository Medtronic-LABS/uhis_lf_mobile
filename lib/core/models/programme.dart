/// The UHIS frontline health programmes surfaced by the AI Worklist.
///
/// The wire-side `diagnosisType[]` field (spice-service `PatientDTO`) and the
/// per-domain detail endpoints (`/medical-review/tb/details`, `/pregnancy/info`,
/// `/immunisation/list`, etc.) carry programme membership in different shapes;
/// [Programme.fromTag] is the single home for the mapping.
///
/// **PILOT-SCOPE v1** — only the 3 care journeys in [kPilotProgrammes] are active.
/// Non-pilot programmes remain in the enum so wire data from the server still
/// deserialises correctly; they are simply gated out of the UI and pathway engine.
/// To expand scope post-pilot, add programmes back to [kPilotProgrammes].
/// Search for `PILOT-SCOPE` across the codebase to find every disabled block.
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

  // ---------------------------------------------------------------------------
  // PILOT-SCOPE v1: active programmes for the July 2026 field pilot.
  // 3 care journeys: sick child (imci), pregnancy (anc/pnc), NCD.
  // To restore a programme: add it here + un-comment blocks tagged PILOT-SCOPE.
  // ---------------------------------------------------------------------------
  static const Set<Programme> kPilotProgrammes = {
    Programme.imci,
    Programme.anc,
    Programme.pnc,
    Programme.ncd,
  };

  /// True when this programme is included in the v1 pilot scope.
  bool get isPilot => kPilotProgrammes.contains(this);

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
      case 'PWPROFILE':
      case 'PW_PROFILE':
        return Programme.anc;
      case 'PNC':
      case 'POSTNATAL':
      // Expanded form-type names used by the unified Step 2 form
      // (visit_form_screen._toFormTypes expands pnc → pncMother + pncChild).
      case 'PNCMOTHER':
      case 'PNC_MOTHER':
      case 'PNCCHILD':
      case 'PNC_CHILD':
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

  /// Human-readable form label shown in visit-flow dialogs and headers.
  String get displayName {
    switch (this) {
      case Programme.imci:
        return 'Child Visit';
      case Programme.anc:
        return 'ANC Visit';
      case Programme.pnc:
        return 'PNC Visit';
      case Programme.ncd:
        return 'NCD Check';
      case Programme.tb:
        return 'TB Check';
      case Programme.epi:
        return 'Vaccination';
      case Programme.nutrition:
        return 'Nutrition';
      case Programme.familyPlanning:
        return 'Family Planning';
      case Programme.cataract:
        return 'Cataract';
      case Programme.eyeCare:
        return 'Eye Care';
      case Programme.unknown:
        return 'Scheduled Visit';
    }
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
