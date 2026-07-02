import '../../scribe/models/ai_extracted_field.dart';
import 'ai_scribe_triage_vocab.dart';

/// Offline fallback: map a scribe transcript to [AiScribeTriageVocab] codes when
/// the AI service returns `triage: null` (SOAP-only pipeline or empty LLM output).
abstract final class TriageTranscriptMatcher {
  TriageTranscriptMatcher._();

  static const double _matchConfidence = 0.75;

  /// English keyword patterns keyed by vocab code. Kept in sync with
  /// [AiScribeTriageVocab.codes] — update both when the vocab changes.
  static const Map<String, List<String>> _patternsByCode = {
    'fever': ['fever', 'febrile', 'high temperature', 'pyrexia'],
    'heavy_bleeding': ['heavy bleeding', 'excessive bleeding', 'profuse bleeding'],
    'vaginal_bleeding': ['vaginal bleeding', 'spotting', 'bleeding per vagina'],
    'foul_smelling_vaginal_discharge': [
      'foul smelling discharge',
      'foul-smelling discharge',
      'bad smelling discharge',
    ],
    'abdominal_pain': ['abdominal pain', 'stomach pain', 'belly pain'],
    'epigastric_pain': ['epigastric pain', 'upper abdominal pain'],
    'headache': ['headache', 'head ache', 'cephalgia'],
    'blurred_vision': ['blurred vision', 'blurry vision', 'vision problem'],
    'convulsions': ['convulsion', 'convulsions', 'seizure', 'fit'],
    'swelling_face_hands': [
      'swelling face',
      'swollen face',
      'swollen hands',
      'puffy face',
      'puffy hands',
    ],
    'edema': ['edema', 'oedema', 'swelling'],
    'breast_pain': ['breast pain', 'painful breast'],
    'breast_swelling': ['breast swelling', 'swollen breast'],
    'perineal_wound_discharge': ['perineal discharge', 'perineal wound'],
    'vomiting': ['vomiting', 'vomits', 'throwing up', 'emesis'],
    'painful_urination': ['painful urination', 'burning urination', 'dysuria'],
    'breathlessness': [
      'breathless',
      'breathlessness',
      'shortness of breath',
      'difficulty breathing',
    ],
    'dizziness': ['dizzy', 'dizziness', 'lightheaded'],
    'leaking_fluid_vagina': [
      'leaking fluid',
      'amniotic fluid',
      'water breaking',
    ],
    'painful_uterine_contractions': [
      'uterine contraction',
      'painful contraction',
      'labour pain',
      'labor pain',
    ],
    'reduced_fetal_movement': [
      'reduced fetal movement',
      'baby not moving',
      'decreased fetal movement',
    ],
    'chest_pain': ['chest pain', 'chest discomfort'],
    'one_sided_weakness': [
      'one sided weakness',
      'one-sided weakness',
      'weakness on one side',
    ],
    'swelling_both_feet': ['swelling both feet', 'swollen feet', 'pedal edema'],
    'palpitations': ['palpitation', 'palpitations', 'racing heart'],
    'swelling_one_leg': ['swelling one leg', 'swollen leg', 'leg swelling'],
    'excessive_thirst': ['excessive thirst', 'very thirsty', 'polydipsia'],
    'foot_numbness': ['foot numbness', 'numb feet', 'numbness in feet'],
    'foot_pain': ['foot pain', 'painful foot'],
    'foot_wound': ['foot wound', 'foot ulcer', 'sore on foot'],
    'fatigue': ['fatigue', 'tired', 'lethargy'],
    'weakness': ['weakness', 'feeling weak', 'general weakness'],
    'weight_loss': ['weight loss', 'losing weight', 'lost weight'],
  };

  /// Phrases that indicate the LLM/ASR produced no usable clinical content.
  static const List<String> _emptyVisitPhrases = [
    'did not provide any verbal complaints',
    'no verbal complaints',
    'no complaints during',
    'denies any symptoms',
    'denies all symptoms',
    'no symptoms mentioned',
    'no symptoms reported',
    'no concerns reported',
    'patient is well',
    'feels fine',
    'unable to assess',
  ];

  /// Builds searchable text from poll result fields when the service returns
  /// `triage: null` (SOAP-only worker). Includes SOAP sections because the
  /// subjective line often carries symptom wording even when raw transcript is
  /// empty or trimmed away by silence removal.
  static String? fallbackSearchText({
    String? transcriptText,
    String? transcriptTranslation,
    String? soapSubjective,
    String? soapObjective,
    String? soapAssessment,
  }) {
    final parts = <String>[
      if (transcriptText != null && transcriptText.trim().isNotEmpty)
        transcriptText.trim(),
      if (transcriptTranslation != null &&
          transcriptTranslation.trim().isNotEmpty)
        transcriptTranslation.trim(),
      if (soapSubjective != null && soapSubjective.trim().isNotEmpty)
        soapSubjective.trim(),
      if (soapObjective != null && soapObjective.trim().isNotEmpty)
        soapObjective.trim(),
      if (soapAssessment != null && soapAssessment.trim().isNotEmpty)
        soapAssessment.trim(),
    ];
    if (parts.isEmpty) return null;

    final combined = parts.join(' ');
    if (_isNonClinicalMetaStatement(combined)) return null;
    return combined;
  }

  /// Returns matched symptom fields, or null when [text] is empty / no matches.
  static TriageExtractionResult? match(
    String text, {
    required List<String> catalog,
    String? noteId,
  }) {
    final normalized = text.trim().toLowerCase();
    if (normalized.length < 3) return null;
    if (_isNonClinicalMetaStatement(normalized)) return null;

    final allowed = catalog.toSet();
    final fields = <AIExtractedField>[];

    for (final code in AiScribeTriageVocab.codes) {
      if (!allowed.contains(code)) continue;
      final patterns = _patternsByCode[code];
      if (patterns == null) continue;

      for (final pattern in patterns) {
        if (!_containsPhrase(normalized, pattern)) continue;
        if (_isNegated(normalized, pattern)) continue;
        fields.add(
          AIExtractedField(
            fieldId: code,
            value: true,
            confidence: _matchConfidence,
            sourceSegment: pattern,
            source: FieldSource.aiPending,
            extractedAt: DateTime.now(),
          ),
        );
        break;
      }
    }

    if (fields.isEmpty) return null;
    return TriageExtractionResult(
      symptomCodes: fields,
      transcriptText: text,
      noteId: noteId,
    );
  }

  static bool _containsPhrase(String haystack, String phrase) =>
      haystack.contains(phrase.toLowerCase());

  static bool _isNegated(String text, String phrase) {
    final index = text.indexOf(phrase.toLowerCase());
    if (index < 0) return false;
    final before = text.substring((index - 30).clamp(0, index), index);
    const negations = ['no ', 'not ', 'denies ', 'without ', 'absent ', 'negative '];
    return negations.any(before.contains);
  }

  static bool _isNonClinicalMetaStatement(String text) {
    final normalized = text.trim().toLowerCase();
    if (normalized.length < 3) return true;

    for (final phrase in _emptyVisitPhrases) {
      if (!normalized.contains(phrase)) continue;
      var remainder = normalized.replaceAll(phrase, '');
      remainder = remainder
          .replaceAll(
            RegExp(
              r'\b(during|the|consultation|visit|today|patient|reports?|states?)\b',
            ),
            ' ',
          )
          .replaceAll(RegExp(r'[^\w\s]'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      if (remainder.length < 15) return true;
    }
    return false;
  }
}
