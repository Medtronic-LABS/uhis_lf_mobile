/// The four UHIS frontline health programmes surfaced by the AI Worklist.
///
/// The wire-side `diagnosisType[]` field (spice-service `PatientDTO`) and the
/// per-domain detail endpoints (`/medical-review/tb/details`, `/pregnancy/info`,
/// `/immunisation/list`, etc.) carry programme membership in different shapes;
/// [Programme.fromTag] is the single home for the mapping.
enum Programme {
  imci,
  anc,
  ncd,
  tb;

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
      case 'PNC':
        return Programme.anc;
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
      case Programme.ncd:
        return 'NCD';
      case Programme.tb:
        return 'TB';
    }
  }

  static Programme? fromWireTag(String? tag) {
    if (tag == null) return null;
    switch (tag.toUpperCase()) {
      case 'IMCI':
        return Programme.imci;
      case 'ANC':
        return Programme.anc;
      case 'NCD':
        return Programme.ncd;
      case 'TB':
        return Programme.tb;
    }
    return null;
  }
}
