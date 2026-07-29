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
    'fever': [
      'fever', 'febrile', 'high temperature', 'pyrexia',
      'জ্বর', 'তাপমাত্রা বেশি',
    ],
    'heavy_bleeding': [
      'heavy bleeding', 'excessive bleeding', 'profuse bleeding',
      'বেশি রক্তপাত', 'প্রচুর রক্তপাত', 'অতিরিক্ত রক্তপাত', 'অতিরিক্ত রক্তক্ষরণ',
    ],
    'vaginal_bleeding': [
      'vaginal bleeding', 'spotting', 'bleeding per vagina',
      'যোনিতে রক্ত', 'যোনিপথে রক্তপাত', 'রক্তস্রাব', 'মাসিকের বাইরে রক্ত',
    ],
    'foul_smelling_vaginal_discharge': [
      'foul smelling discharge',
      'foul-smelling discharge',
      'bad smelling discharge',
      'দুর্গন্ধযুক্ত স্রাব', 'পচা গন্ধ স্রাব', 'দুর্গন্ধ স্রাব', 'স্রাবে গন্ধ',
    ],
    'abdominal_pain': [
      'abdominal pain', 'stomach pain', 'belly pain',
      'পেটে ব্যথা', 'পেট ব্যথা', 'তলপেটে ব্যথা', 'পেটব্যথা',
    ],
    'epigastric_pain': [
      'epigastric pain', 'upper abdominal pain',
      'বুকের নিচে ব্যথা', 'পেটের উপরে ব্যথা', 'উপরিভাগে ব্যথা',
    ],
    'headache': [
      'headache', 'head ache', 'cephalgia',
      'মাথা ব্যথা', 'মাথাব্যথা', 'মাথায় ব্যথা',
    ],
    'blurred_vision': [
      'blurred vision', 'blurry vision', 'vision problem',
      'চোখে ঝাপসা', 'দৃষ্টি ঝাপসা', 'চোখে অন্ধকার', 'চোখে কম দেখা',
    ],
    'convulsions': [
      'convulsion', 'convulsions', 'seizure', 'fit',
      'খিঁচুনি', 'খিচুনি', 'ঝাঁকুনি', 'ফিট হয়েছে',
    ],
    'swelling_face_hands': [
      'swelling face',
      'swollen face',
      'swollen hands',
      'puffy face',
      'puffy hands',
      'মুখ ফুলা', 'হাত ফুলা', 'মুখ ফোলা', 'হাত ফোলা',
    ],
    'edema': [
      'edema', 'oedema', 'swelling',
      'ফোলা', 'ফুলা', 'শোথ', 'পা ফোলা', 'পা ফুলা',
    ],
    'breast_pain': [
      'breast pain', 'painful breast',
      'স্তনে ব্যথা', 'স্তন ব্যথা', 'বুকে ব্যথা স্তন',
    ],
    'breast_swelling': [
      'breast swelling', 'swollen breast',
      'স্তন ফুলা', 'স্তন ফোলা',
    ],
    'perineal_wound_discharge': [
      'perineal discharge', 'perineal wound',
      'পেরিনিয়ামে ক্ষত', 'সেলাইয়ের জায়গায় স্রাব', 'নিচের কাটা জায়গায়',
    ],
    'vomiting': [
      'vomiting', 'vomits', 'throwing up', 'emesis',
      'বমি', 'বমি বমি ভাব', 'বমি করছি', 'বমি হচ্ছে',
    ],
    'painful_urination': [
      'painful urination', 'burning urination', 'dysuria',
      'প্রস্রাবে জ্বালা', 'প্রস্রাবে ব্যথা', 'প্রস্রাব করতে ব্যথা', 'জ্বালাপোড়া',
    ],
    'breathlessness': [
      'breathless',
      'breathlessness',
      'shortness of breath',
      'difficulty breathing',
      'শ্বাসকষ্ট', 'শ্বাস নিতে কষ্ট', 'শ্বাস নিতে সমস্যা', 'শ্বাস কষ্ট',
    ],
    'dizziness': [
      'dizzy', 'dizziness', 'lightheaded',
      'মাথা ঘোরা', 'মাথাঘোরা', 'মাথা ঘুরছে',
    ],
    'leaking_fluid_vagina': [
      'leaking fluid',
      'amniotic fluid',
      'water breaking',
      'পানি ভাঙা', 'তরল বের হচ্ছে', 'পানি বের হচ্ছে', 'পানি ভেঙেছে',
    ],
    'painful_uterine_contractions': [
      'uterine contraction',
      'painful contraction',
      'labour pain',
      'labor pain',
      'ব্যথা উঠেছে', 'প্রসব ব্যথা', 'জরায়ু ব্যথা', 'পেটে টান',
    ],
    'reduced_fetal_movement': [
      'reduced fetal movement',
      'baby not moving',
      'decreased fetal movement',
      'বাচ্চা নড়ছে না', 'বাচ্চার নড়াচড়া কম', 'ভ্রূণ নড়ছে না',
    ],
    'chest_pain': [
      'chest pain', 'chest discomfort',
      'বুকে ব্যথা', 'বুক ব্যথা', 'বুকব্যথা',
    ],
    'one_sided_weakness': [
      'one sided weakness',
      'one-sided weakness',
      'weakness on one side',
      'এক পাশে দুর্বলতা', 'এক দিকে দুর্বলতা', 'এক পাশ দুর্বল',
    ],
    'swelling_both_feet': [
      'swelling both feet', 'swollen feet', 'pedal edema',
      'দুই পা ফোলা', 'দুই পা ফুলা', 'দুপায়ে ফোলা',
    ],
    'palpitations': [
      'palpitation', 'palpitations', 'racing heart',
      'বুক ধড়ফড়', 'হার্টবিট বেশি', 'বুক দ্রুত চলছে',
    ],
    'swelling_one_leg': [
      'swelling one leg', 'swollen leg', 'leg swelling',
      'এক পা ফোলা', 'এক পা ফুলা', 'এক পায়ে ফোলা',
    ],
    'excessive_thirst': [
      'excessive thirst', 'very thirsty', 'polydipsia',
      'অতিরিক্ত তৃষ্ণা', 'বেশি তৃষ্ণা', 'বেশি তেষ্টা', 'খুব তেষ্টা',
    ],
    'foot_numbness': [
      'foot numbness', 'numb feet', 'numbness in feet',
      'পায়ে অসাড়', 'পায়ে সাড় নেই', 'পা অসাড়',
    ],
    'foot_pain': [
      'foot pain', 'painful foot',
      'পায়ে ব্যথা', 'পা ব্যথা',
    ],
    'foot_wound': [
      'foot wound', 'foot ulcer', 'sore on foot',
      'পায়ে ঘা', 'পায়ে ক্ষত', 'পায়ে আলসার',
    ],
    'fatigue': [
      'fatigue', 'tired', 'lethargy',
      'ক্লান্তি', 'ক্লান্ত', 'অবসাদ', 'শ্রান্তি',
    ],
    'weakness': [
      'weakness', 'feeling weak', 'general weakness',
      'দুর্বলতা', 'দুর্বল', 'শক্তি নেই', 'অশক্তি',
    ],
    'weight_loss': [
      'weight loss', 'losing weight', 'lost weight',
      'ওজন কমছে', 'ওজন কমে গেছে', 'ওজন হ্রাস',
    ],
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
