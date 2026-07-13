/// Maps triage symptom codes (from Step 1) to pre-fill values for clinical
/// form fields (Step 2) and to the set of codes relevant to each programme.
///
/// These are best-effort suggestions: fields are only pre-filled when the
/// canonical data store has no existing value, so saved drafts always win.
///
/// ## Mapping rationale
///
/// | formType | field seeded | option-ID format |
/// |---|---|---|
/// | `ncd` | `ncdSymptoms` (DialogCheckbox) | display names ("Headache") |
/// | `ncd` | `hasSymptoms` (radio) | `"Yes"` if any NCD symptom maps |
/// | `anc` | `ancDangerSigns` (DialogCheckbox) | camelCase IDs |
/// | `pncMother` | `postpartumDangerSigns` (DialogCheckbox) | numeric string IDs |
abstract final class TriageSymptomMapper {
  TriageSymptomMapper._();

  // ── NCD symptoms ──────────────────────────────────────────────────────────
  // Option IDs for `ncdSymptoms` equal their display name.

  static const Map<String, String> _ncdSymptomByCode = {
    'headache': 'Headache',
    'blurred_vision': 'Blurred Vision',
    'chest_pain': 'Chest Pain',
    'breathlessness': 'Shortness of Breath',
    'one_sided_weakness': 'Weakness',
    'foot_numbness': 'Numbness',
    'dizziness': 'Dizziness',
    'palpitations': 'Palpitations',
    'swelling_both_feet': 'Leg Swelling',
    'swelling_one_leg': 'Leg Swelling',
    'excessive_thirst': 'Excessive Thirst',
    'weight_loss': 'Unexplained Weight Loss',
    'epigastric_pain': 'Chest Pain', // closest NCD option
  };

  // ── ANC danger signs ──────────────────────────────────────────────────────
  // Option IDs for `ancDangerSigns` are camelCase.

  static const Map<String, String> _ancDangerSignByCode = {
    'heavy_bleeding': 'vaginalBleeding',
    'vaginal_bleeding': 'vaginalBleeding',
    'leaking_fluid_vagina': 'leakingFluid',
    'painful_uterine_contractions': 'painfulContractions',
    'headache': 'headacheVision',
    'blurred_vision': 'headacheVision',
    'swelling_face_hands': 'headacheVision',
    'epigastric_pain': 'epigastricPain',
    'reduced_fetal_movement': 'reducedFetalMovement',
    'painful_urination': 'feverUrination',
    'fever': 'feverUrination',
  };

  // ── PNC (postpartum) danger signs ─────────────────────────────────────────
  // Option IDs for `postpartumDangerSigns` are numeric strings.

  static const Map<String, String> _pncDangerSignByCode = {
    'heavy_bleeding': '1',
    'vaginal_bleeding': '1',
    'foul_smelling_vaginal_discharge': '2',
    'abdominal_pain': '3',
    'headache': '4',
    'blurred_vision': '4',
    'convulsions': '4',
    'perineal_wound_discharge': '5',
    'breast_pain': '6',
    'breast_swelling': '6',
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Returns field-id → value pairs to pre-seed for [formType].
  ///
  /// Only formTypes that have a known mapping produce output; others return an
  /// empty map.  Values are lists (for multi-select) or strings (for radio).
  static Map<String, dynamic> prefillsFor(
    String formType,
    List<String> triageCodes,
  ) {
    switch (formType) {
      case 'ncd':
        final matched = _uniqueValues(triageCodes, _ncdSymptomByCode);
        if (matched.isEmpty) return const {};
        return {
          'ncdSymptoms': matched,
          'hasSymptoms': 'Yes',
        };
      case 'anc':
        final matched = _uniqueValues(triageCodes, _ancDangerSignByCode);
        if (matched.isEmpty) return const {};
        return {'ancDangerSigns': matched};
      case 'pncMother':
        final matched = _uniqueValues(triageCodes, _pncDangerSignByCode);
        if (matched.isEmpty) return const {};
        return {'postpartumDangerSigns': matched};
      default:
        return const {};
    }
  }

  /// Returns the subset of [triageCodes] that are relevant to [formType].
  ///
  /// Used by the programme divider to display contextual symptom chips.
  static List<String> relevantCodes(
    String formType,
    List<String> triageCodes,
  ) {
    final Map<String, Object> map;
    switch (formType) {
      case 'ncd':
        return const []; // NCD symptoms pre-filled into fields; no divider chips
      case 'anc':
      case 'pncMother':
      case 'pncChild':
        map = _ancDangerSignByCode;
      default:
        return const [];
    }
    return triageCodes.where(map.containsKey).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  static List<String> _uniqueValues(
    List<String> codes,
    Map<String, String> mapping,
  ) {
    final seen = <String>{};
    return [
      for (final c in codes)
        if (mapping.containsKey(c) && seen.add(mapping[c]!)) mapping[c]!,
    ];
  }
}
