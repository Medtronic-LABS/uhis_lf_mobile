import '../visit/triage/ai_scribe_triage_vocab.dart';

/// Maps free-text `chiefComplaints` phrases (from the live-ASR general
/// clinical-extraction prompt, e.g. "fever", "vaginal bleeding") to
/// [AiScribeTriageVocab] codes via keyword matching.
///
/// This exists because the live-ASR endpoint (ai-scribe-service's general
/// `run_inference`) has no concept of this app's fixed symptom vocab — it
/// only extracts natural-language chief complaints. The proper long-term fix
/// is a vocab-constrained extraction prompt server-side (like the batch
/// "triage" mode is meant to use); this keyword matcher is a client-side
/// stand-in so live-detected symptoms can still pre-tick chips today.
///
/// Chief complaints are expected in English regardless of spoken language
/// (confirmed in testing: the extraction prompt normalizes non-English
/// complaints to English chief-complaint phrases).
abstract final class ChiefComplaintMatcher {
  ChiefComplaintMatcher._();

  /// Confidence assigned to keyword matches — comfortably above
  /// [AppConfig.scribeSymptomConfidenceFloor] (0.7 default) but below the
  /// 1.0 reserved for verbatim server-side vocab-constrained extraction.
  static const double matchConfidence = 0.85;

  static const Map<String, List<String>> _keywordsByCode = {
    'fever': ['fever', 'high temperature', 'high temp'],
    'heavy_bleeding': ['heavy bleeding', 'excessive bleeding', 'heavy vaginal bleeding'],
    'vaginal_bleeding': ['vaginal bleeding', 'bleeding per vagina', 'pv bleeding', 'spotting'],
    'foul_smelling_vaginal_discharge': [
      'foul smelling discharge',
      'foul-smelling discharge',
      'smelly discharge',
      'vaginal discharge',
    ],
    'abdominal_pain': ['abdominal pain', 'stomach pain', 'belly pain', 'abdomen pain'],
    'epigastric_pain': ['epigastric pain', 'upper abdominal pain'],
    'headache': ['headache', 'head pain', 'head ache'],
    'blurred_vision': ['blurred vision', 'blurry vision', 'vision problem', 'visual disturbance'],
    'convulsions': ['convulsion', 'seizure', 'fits'],
    'swelling_face_hands': [
      'swelling of face',
      'facial swelling',
      'swollen face',
      'swelling in hands',
      'swollen hands',
    ],
    'edema': ['edema', 'oedema'],
    'breast_pain': ['breast pain', 'painful breast'],
    'breast_swelling': ['breast swelling', 'swollen breast'],
    'perineal_wound_discharge': ['perineal wound', 'perineal discharge', 'episiotomy discharge'],
    'vomiting': ['vomiting', 'vomit', 'throwing up'],
    'painful_urination': ['painful urination', 'burning urination', 'dysuria', 'pain while urinating'],
    'breathlessness': ['breathlessness', 'shortness of breath', 'difficulty breathing', 'breathless'],
    'dizziness': ['dizziness', 'dizzy', 'lightheaded', 'light headed', 'vertigo'],
    'leaking_fluid_vagina': ['leaking fluid', 'fluid leakage', 'water breaking', 'rupture of membranes'],
    'painful_uterine_contractions': ['uterine contraction', 'labor pain', 'labour pain', 'contractions'],
    'reduced_fetal_movement': ['reduced fetal movement', 'decreased fetal movement', 'baby not moving'],
    'chest_pain': ['chest pain', 'pain in chest'],
    'one_sided_weakness': [
      'one sided weakness',
      'one-sided weakness',
      'weakness on one side',
      'facial droop',
    ],
    'swelling_both_feet': ['swelling both feet', 'swollen feet', 'swelling of feet', 'swelling in both legs'],
    'palpitations': ['palpitation', 'heart racing', 'rapid heartbeat'],
    'swelling_one_leg': ['swelling one leg', 'swollen leg', 'one leg swelling'],
    'excessive_thirst': ['excessive thirst', 'increased thirst', 'polydipsia'],
    'foot_numbness': ['foot numbness', 'numbness in feet', 'numb feet', 'tingling feet'],
    'foot_pain': ['foot pain', 'pain in foot', 'pain in feet'],
    'foot_wound': ['foot wound', 'foot ulcer', 'wound on foot', 'diabetic foot'],
    'fatigue': ['fatigue', 'tiredness', 'feeling tired'],
    'weakness': ['weakness', 'feeling weak', 'generalized weakness'],
    'weight_loss': ['weight loss', 'losing weight', 'unintentional weight loss'],
  };

  /// Returns the vocab codes matched by any of [chiefComplaints]. Codes not
  /// in [AiScribeTriageVocab.codes] can never appear (the keyword table is
  /// keyed by vocab code), so this is safe to feed straight into
  /// TriageViewModel.applyScribeTriageResult without further filtering.
  static Set<String> match(List<String> chiefComplaints) {
    final matched = <String>{};
    for (final complaint in chiefComplaints) {
      final normalized = complaint.toLowerCase();
      for (final entry in _keywordsByCode.entries) {
        if (matched.contains(entry.key)) continue;
        if (entry.value.any(normalized.contains)) {
          matched.add(entry.key);
        }
      }
    }
    return matched;
  }
}
