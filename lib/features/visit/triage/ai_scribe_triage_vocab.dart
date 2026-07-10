/// Single home for the symptom codes the AI Scribe is allowed to extract on
/// Step 1 of the visit flow.
///
/// The AI service is told *only* to return codes from this list — any other
/// detected symptom is dropped. The SK can still tick any extra symptoms
/// manually; this list constrains the AI side only.
///
/// Source: Apon Sushashthya V1 §4.1.2 (ANC) + §5.1.1 (NCD) auto-detect
/// candidates. Update both this file and the AI service prompt together —
/// drift between client + service is the main failure mode.
library;

import '../../../core/models/programme.dart';
import 'patient_context_builder.dart';

/// Category a vocab code belongs to. Drives demographic pre-screening so the
/// SK never sees questions irrelevant to the patient (no maternal symptoms
/// for males, no NCD-aging symptoms for under-18s, etc).
enum SymptomCategory {
  /// Applicable to all patients.
  general,

  /// Maternal / obstetric / breast symptoms — gated to female reproductive age.
  maternal,

  /// NCD / chronic-disease screening symptoms — gated to adults.
  ncd,

  /// Paediatric-specific symptoms — gated to under-5s.
  pediatric,
}

abstract final class AiScribeTriageVocab {
  AiScribeTriageVocab._();

  /// Reproductive age window for the maternal gate, in months.
  /// 14 years → 44 years (pilot programme scope: female patients who may be pregnant).
  static const int maternalMinAgeMonths = 168;
  static const int maternalMaxAgeMonths = 528;

  /// Adult threshold for the NCD gate, in months (18 years).
  static const int _ncdMinAgeMonths = 216;

  /// Paediatric ceiling, in months (under 5 years).
  static const int _pediatricMaxAgeMonths = 60;

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

  /// Category tag per code. Source of truth for demographic pre-screening.
  static const Map<String, SymptomCategory> _categoryByCode = {
    'fever': SymptomCategory.general,
    'heavy_bleeding': SymptomCategory.maternal,
    'vaginal_bleeding': SymptomCategory.maternal,
    'foul_smelling_vaginal_discharge': SymptomCategory.maternal,
    'abdominal_pain': SymptomCategory.general,
    'epigastric_pain': SymptomCategory.ncd,
    'headache': SymptomCategory.general,
    'blurred_vision': SymptomCategory.general,
    'convulsions': SymptomCategory.general,
    'swelling_face_hands': SymptomCategory.maternal,
    'edema': SymptomCategory.maternal,
    'breast_pain': SymptomCategory.maternal,
    'breast_swelling': SymptomCategory.maternal,
    'perineal_wound_discharge': SymptomCategory.maternal,
    'vomiting': SymptomCategory.general,
    'painful_urination': SymptomCategory.general,
    'breathlessness': SymptomCategory.general,
    'dizziness': SymptomCategory.general,
    'leaking_fluid_vagina': SymptomCategory.maternal,
    'painful_uterine_contractions': SymptomCategory.maternal,
    'reduced_fetal_movement': SymptomCategory.maternal,
    'chest_pain': SymptomCategory.ncd,
    'one_sided_weakness': SymptomCategory.ncd,
    'swelling_both_feet': SymptomCategory.ncd,
    'palpitations': SymptomCategory.ncd,
    'swelling_one_leg': SymptomCategory.ncd,
    'excessive_thirst': SymptomCategory.ncd,
    'foot_numbness': SymptomCategory.ncd,
    'foot_pain': SymptomCategory.ncd,
    'foot_wound': SymptomCategory.ncd,
    'fatigue': SymptomCategory.general,
    'weakness': SymptomCategory.general,
    'weight_loss': SymptomCategory.general,
  };

  /// Precise programme-level mapping for maternal-category vocab codes.
  ///
  /// Maternal codes are further split by care journey:
  ///   - ANC  — ante-natal danger signs (pre-eclampsia, fetal, labour)
  ///   - PNC  — post-natal / breast / perineal signs
  ///   - Both — bleeding / discharge that spans both journeys
  ///
  /// A code absent from this map is treated as applicable to **both** ANC and
  /// PNC so future additions are always visible rather than silently hidden.
  static const Map<String, Set<Programme>> _maternalCodeProgrammes = {
    // ── ANC-specific ──────────────────────────────────────────────────────
    'swelling_face_hands': {Programme.anc},
    'edema': {Programme.anc},
    'leaking_fluid_vagina': {Programme.anc},
    'painful_uterine_contractions': {Programme.anc},
    'reduced_fetal_movement': {Programme.anc},
    // ── PNC-specific ──────────────────────────────────────────────────────
    'breast_pain': {Programme.pnc},
    'breast_swelling': {Programme.pnc},
    'perineal_wound_discharge': {Programme.pnc},
    'foul_smelling_vaginal_discharge': {Programme.pnc},
    // ── Both journeys ─────────────────────────────────────────────────────
    'heavy_bleeding': {Programme.anc, Programme.pnc},
    'vaginal_bleeding': {Programme.anc, Programme.pnc},
  };

  /// Returns the specific programmes a maternal-category [code] is relevant
  /// to. Codes not in [_maternalCodeProgrammes] return both ANC and PNC so
  /// they are never accidentally hidden.
  static Set<Programme> programmesForMaternalCode(String code) =>
      _maternalCodeProgrammes[code] ?? {Programme.anc, Programme.pnc};

  /// Lookup the category for a vocab code. Unknown codes default to
  /// [SymptomCategory.general] so a future addition doesn't silently disappear.
  static SymptomCategory categoryOf(String code) =>
      _categoryByCode[code] ?? SymptomCategory.general;

  /// Whether [code] is applicable to a patient with the given demographic
  /// context. Used to pre-screen the symptom list before render and to drop
  /// AI-detected codes that don't apply to this patient.
  ///
  /// Rules:
  ///   - general → always
  ///   - maternal → female AND ageMonths within reproductive window
  ///   - ncd → ageMonths >= adult threshold (18+)
  ///   - paediatric → ageMonths < 60 (under 5)
  static bool isApplicable(String code, PatientContext ctx) {
    switch (categoryOf(code)) {
      case SymptomCategory.general:
        return true;
      case SymptomCategory.maternal:
        return ctx.sex == Sex.female &&
            ctx.ageMonths >= maternalMinAgeMonths &&
            ctx.ageMonths <= maternalMaxAgeMonths;
      case SymptomCategory.ncd:
        return ctx.ageMonths >= _ncdMinAgeMonths;
      case SymptomCategory.pediatric:
        return ctx.ageMonths < _pediatricMaxAgeMonths;
    }
  }

  /// Vocab codes applicable to [ctx], in vocab declaration order.
  static List<String> applicableCodes(PatientContext ctx) =>
      codes.where((c) => isApplicable(c, ctx)).toList(growable: false);

  /// Human-readable label for a code — used when the AI surfaces a code that
  /// isn't present in TriageStrings. Underscores → spaces, capitalised words.
  static String labelFor(String code) {
    return code
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
