/// Single home for the symptom codes the AI Scribe is allowed to extract on
/// Step 1 of the visit flow.
///
/// The AI service is told *only* to return codes from this list — any other
/// detected symptom is dropped. The SK can still tick any extra symptoms in
/// the full UnifiedSymptomCatalog manually; this list constrains the AI side
/// only.
///
/// Source: Apon Sushashthya V1 §4.1.2 (ANC) + §5.1.1 (NCD) auto-detect
/// candidates. Update both this file and the AI service prompt together —
/// drift between client + service is the main failure mode.
library;

abstract final class AiScribeTriageVocab {
  AiScribeTriageVocab._();

  /// The 32 symptom codes the AI Scribe may return. Order is significant —
  /// the AI service preserves it when reporting confidence per code.
  static const List<String> codes = <String>[
    'fever',
    'heavy_bleeding',
    'vaginal_bleeding',
    'foul_smelling_vaginal_discharge',
    'abdominal_pain',
    'epigastric_pain',
    'headache',
    'blurred_vision',
    'convulsions',
    'swelling_face_hands',
    'edema',
    'breast_pain',
    'breast_swelling',
    'perineal_wound_discharge',
    'vomiting',
    'painful_urination',
    'breathlessness',
    'dizziness',
    'leaking_fluid_vagina',
    'painful_uterine_contractions',
    'reduced_fetal_movement',
    'chest_pain',
    'one_sided_weakness',
    'swelling_both_feet',
    'palpitations',
    'swelling_one_leg',
    'excessive_thirst',
    'foot_numbness',
    'foot_pain',
    'foot_wound',
    'fatigue',
    'weakness',
    'weight_loss',
  ];

  /// Human-readable label for a code — used as the chip label in the
  /// symptom picker when the AI surfaces a code that isn't present in
  /// [UnifiedSymptomCatalog]. Underscores → spaces, capitalised words.
  static String labelFor(String code) {
    return code
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
