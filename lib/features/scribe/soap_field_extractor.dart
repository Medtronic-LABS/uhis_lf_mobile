/// Extracts structured field values from SOAP note text.
///
/// When the backend only returns SOAP (no form_prefill support), this
/// parses the SOAP objective section to extract vitals and clinical values
/// that can be mapped to assessment form fields.
library;

import 'package:flutter/foundation.dart';

import '../../core/api/scribe_api_service.dart';
import 'models/ai_extracted_field.dart';

/// Extracts clinical field values from SOAP notes.
class SoapFieldExtractor {
  const SoapFieldExtractor._();

  /// Extract fields from a SOAP note's objective section.
  ///
  /// Returns a list of [AIExtractedField] that can be used to populate
  /// assessment forms. Each field includes the source text from the SOAP
  /// note for audit trail.
  static List<AIExtractedField> extractFromSoap(SoapNote soap) {
    final fields = <AIExtractedField>[];
    final objective = soap.objective ?? '';
    final subjective = soap.subjective ?? '';
    
    debugPrint('[SoapFieldExtractor] subjective length: ${subjective.length}, objective length: ${objective.length}');
    debugPrint('[SoapFieldExtractor] subjective text: "$subjective"');
    debugPrint('[SoapFieldExtractor] objective text: "$objective"');
    
    // Combine both sections - vitals can appear in either
    final combinedText = '$subjective\n$objective';
    debugPrint('[SoapFieldExtractor] combined text length: ${combinedText.length}');
    
    // Extract vitals from both sections (may contain measurements)
    fields.addAll(_extractVitals(combinedText));
    
    // Extract symptoms from subjective
    fields.addAll(_extractSymptoms(subjective));
    
    return fields;
  }

  /// Extract vital signs and measurements from objective text.
  static List<AIExtractedField> _extractVitals(String text) {
    final fields = <AIExtractedField>[];
    final lowerText = text.toLowerCase();

    // Weight: "weight of 75 kg", "weight: 65 kg", "65kg", "weighs 65 kilograms"
    final weightMatch = RegExp(
      r'weight\s*(?:of|is|:)?\s*(\d+(?:\.\d+)?)\s*(?:kg|kilograms?)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (weightMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'weight',
        value: weightMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: weightMatch.group(0)!,
      ));
    }

    // Height: "height of 170 cm", "height: 170 cm", "170cm tall", "height is 175"
    final heightMatch = RegExp(
      r'height\s*(?:of|is|:)?\s*(\d+(?:\.\d+)?)\s*(?:cm|centimeters?)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (heightMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'height',
        value: heightMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: heightMatch.group(0)!,
      ));
    }

    // Temperature: "temperature: 37.5°C", "temp 98.6F", "fever of 38.2"
    final tempMatch = RegExp(
      r'(?:temp(?:erature)?\s*(?:of|is|:)?\s*|fever\s+(?:of\s+)?)(\d+(?:\.\d+)?)\s*[°]?(?:C|F|celsius|fahrenheit)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (tempMatch != null) {
      var tempValue = double.tryParse(tempMatch.group(1)!) ?? 0;
      // Convert Fahrenheit to Celsius if > 50 (likely F)
      if (tempValue > 50) {
        tempValue = (tempValue - 32) * 5 / 9;
      }
      fields.add(AIExtractedField(
        fieldId: 'temperature',
        value: tempValue.toStringAsFixed(1),
        confidence: 0.80,
        sourceSegment: tempMatch.group(0)!,
      ));
    }

    // Blood Pressure: "BP: 120/80", "blood pressure is measured at 120/80 mmHg", "bp of 130/85"
    final bpMatch = RegExp(
      r'(?:bp|blood\s*pressure)\s*(?:is|of|:)?\s*(?:measured\s*(?:at)?)?\s*(\d{2,3})\s*/\s*(\d{2,3})',
      caseSensitive: false,
    ).firstMatch(text);
    if (bpMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'systolic',
        value: bpMatch.group(1)!,
        confidence: 0.90,
        sourceSegment: bpMatch.group(0)!,
      ));
      fields.add(AIExtractedField(
        fieldId: 'diastolic',
        value: bpMatch.group(2)!,
        confidence: 0.90,
        sourceSegment: bpMatch.group(0)!,
      ));
    }

    // Heart Rate / Pulse: "pulse: 72 bpm", "HR 80", "heart rate 75"
    final hrMatch = RegExp(
      r'(?:pulse|hr|heart\s*rate)\s*(?:is|of|:)?\s*(\d{2,3})\s*(?:bpm|beats)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (hrMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'pulse',
        value: hrMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: hrMatch.group(0)!,
      ));
    }

    // Blood Glucose: "glucose: 120 mg/dL", "blood sugar of 95", "RBS 140", "glucose is 110"
    final glucoseMatch = RegExp(
      r'(?:glucose|blood\s*sugar|rbs|fbs|ppbs)\s*(?:of|is|:)?\s*(\d{2,3})\s*(?:mg/?dl)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (glucoseMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'glucose',
        value: glucoseMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: glucoseMatch.group(0)!,
      ));
      
      // Determine glucose type from context
      if (lowerText.contains('fasting') || lowerText.contains('fbs')) {
        fields.add(AIExtractedField(
          fieldId: 'glucoseType',
          value: 'fasting',
          confidence: 0.90,
          sourceSegment: glucoseMatch.group(0)!,
        ));
      } else if (lowerText.contains('post') || lowerText.contains('ppbs') || lowerText.contains('after meal')) {
        fields.add(AIExtractedField(
          fieldId: 'glucoseType',
          value: 'postprandial',
          confidence: 0.90,
          sourceSegment: glucoseMatch.group(0)!,
        ));
      } else if (lowerText.contains('random') || lowerText.contains('rbs')) {
        fields.add(AIExtractedField(
          fieldId: 'glucoseType',
          value: 'random',
          confidence: 0.90,
          sourceSegment: glucoseMatch.group(0)!,
        ));
      }
    }

    // HbA1c: "HbA1c: 7.2%", "A1c 6.5"
    final hba1cMatch = RegExp(
      r'(?:hba1c|a1c)[:\s]*(\d+(?:\.\d+)?)\s*%?',
      caseSensitive: false,
    ).firstMatch(text);
    if (hba1cMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'hba1c',
        value: hba1cMatch.group(1)!,
        confidence: 0.90,
        sourceSegment: hba1cMatch.group(0)!,
      ));
    }

    // SpO2 / Oxygen saturation: "SpO2: 98%", "oxygen saturation 97%"
    final spo2Match = RegExp(
      r'(?:spo2|oxygen\s*saturation|o2\s*sat)[:\s]*(\d{2,3})\s*%?',
      caseSensitive: false,
    ).firstMatch(text);
    if (spo2Match != null) {
      fields.add(AIExtractedField(
        fieldId: 'spo2',
        value: spo2Match.group(1)!,
        confidence: 0.85,
        sourceSegment: spo2Match.group(0)!,
      ));
    }

    // Respiratory rate: "RR: 18", "respiratory rate 20"
    final rrMatch = RegExp(
      r'(?:rr|respiratory\s*rate)[:\s]*(\d{1,2})\s*(?:breaths)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (rrMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'respiratoryRate',
        value: rrMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: rrMatch.group(0)!,
      ));
    }

    // MUAC (mid-upper arm circumference): "MUAC: 12.5 cm", "muac 13cm"
    final muacMatch = RegExp(
      r'(?:muac)[:\s]*(\d+(?:\.\d+)?)\s*(?:cm)?',
      caseSensitive: false,
    ).firstMatch(text);
    if (muacMatch != null) {
      fields.add(AIExtractedField(
        fieldId: 'muac',
        value: muacMatch.group(1)!,
        confidence: 0.85,
        sourceSegment: muacMatch.group(0)!,
      ));
    }

    // Smoking status - check for any mention of smoking/smoke
    if (lowerText.contains('smoker') || 
        lowerText.contains('smokes') || 
        lowerText.contains('smoking') ||
        lowerText.contains('smoke')) {
      final isNonSmoker = lowerText.contains('non-smoker') || 
                          lowerText.contains('non smoker') ||
                          lowerText.contains('no smoking') ||
                          lowerText.contains('not smoke') ||
                          lowerText.contains('do not smoke') ||
                          lowerText.contains('does not smoke') ||
                          lowerText.contains('doesn\'t smoke') ||
                          lowerText.contains('denies smoking');
      fields.add(AIExtractedField(
        fieldId: 'smoker',
        value: isNonSmoker ? 'false' : 'true',
        confidence: 0.80,
        sourceSegment: 'smoking status',
      ));
    }

    // Pregnant status (for ANC)
    if (lowerText.contains('pregnant') || lowerText.contains('pregnancy')) {
      fields.add(AIExtractedField(
        fieldId: 'pregnant',
        value: 'true',
        confidence: 0.95,
        sourceSegment: 'pregnancy status',
      ));
    }

    // Gestational age: "12 weeks pregnant", "GA: 28 weeks"
    final gaMatch = RegExp(
      r'(?:ga[:\s]*|gestational\s*age[:\s]*|(\d+)\s*weeks?\s*(?:pregnant|gestation))',
      caseSensitive: false,
    ).firstMatch(text);
    if (gaMatch != null) {
      final weeks = gaMatch.group(1);
      if (weeks != null) {
        fields.add(AIExtractedField(
          fieldId: 'gestationalAge',
          value: weeks,
          confidence: 0.85,
          sourceSegment: gaMatch.group(0)!,
        ));
      }
    }

    return fields;
  }

  /// Extract symptoms from subjective text.
  static List<AIExtractedField> _extractSymptoms(String text) {
    final fields = <AIExtractedField>[];
    final lowerText = text.toLowerCase();

    // Common symptoms with field IDs
    final symptomPatterns = {
      'fever': ['fever', 'febrile', 'pyrexia', 'high temperature'],
      'cough': ['cough', 'coughing'],
      'diarrhea': ['diarrhea', 'diarrhoea', 'loose stools', 'watery stools'],
      'vomiting': ['vomiting', 'vomits', 'emesis', 'throwing up'],
      'headache': ['headache', 'head ache', 'cephalgia'],
      'fatigue': ['fatigue', 'tired', 'weakness', 'lethargy'],
      'abdominalPain': ['abdominal pain', 'stomach pain', 'belly pain', 'epigastric pain'],
      'chestPain': ['chest pain', 'chest discomfort'],
      'breathingDifficulty': ['difficulty breathing', 'shortness of breath', 'dyspnea', 'breathless'],
      'rash': ['rash', 'skin lesion', 'skin eruption'],
      'soreThroat': ['sore throat', 'throat pain', 'pharyngitis'],
      'runnyNose': ['runny nose', 'rhinorrhea', 'nasal discharge'],
      'earPain': ['ear pain', 'otalgia', 'earache'],
      'convulsions': ['convulsion', 'seizure', 'fit'],
      'notEating': ['not eating', 'poor appetite', 'anorexia', 'not feeding'],
      'bloodInStool': ['blood in stool', 'bloody stool', 'melena', 'hematochezia'],
    };

    for (final entry in symptomPatterns.entries) {
      final fieldId = entry.key;
      final patterns = entry.value;
      
      for (final pattern in patterns) {
        if (lowerText.contains(pattern)) {
          // Check for negation
          final negated = _isNegated(lowerText, pattern);
          fields.add(AIExtractedField(
            fieldId: fieldId,
            value: negated ? 'false' : 'true',
            confidence: negated ? 0.70 : 0.85,
            sourceSegment: pattern,
          ));
          break; // Only add once per field
        }
      }
    }

    // Duration of illness: "sick for 3 days", "symptoms for 2 weeks"
    final durationMatch = RegExp(
      r'(?:for|since|past)\s*(\d+)\s*(days?|weeks?|hours?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (durationMatch != null) {
      int days = int.tryParse(durationMatch.group(1)!) ?? 0;
      final unit = durationMatch.group(2)!.toLowerCase();
      if (unit.startsWith('week')) {
        days *= 7;
      } else if (unit.startsWith('hour')) {
        days = 1; // Round up to 1 day
      }
      fields.add(AIExtractedField(
        fieldId: 'durationDays',
        value: days.toString(),
        confidence: 0.80,
        sourceSegment: durationMatch.group(0)!,
      ));
    }

    return fields;
  }

  /// Check if a symptom is negated in the text.
  static bool _isNegated(String text, String symptom) {
    final index = text.indexOf(symptom);
    if (index < 0) return false;

    // Check for negation words before the symptom (within 30 chars)
    final before = text.substring((index - 30).clamp(0, index), index);
    final negationWords = ['no ', 'not ', 'denies ', 'without ', 'absent ', 'negative '];
    
    for (final neg in negationWords) {
      if (before.contains(neg)) return true;
    }
    return false;
  }
}
