import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/forms/triage_symptom_mapper.dart';

void main() {
  group('TriageSymptomMapper.prefillsFor ncd', () {
    test('maps catalog codes to field_library option ids', () {
      final prefills = TriageSymptomMapper.prefillsFor('ncd', [
        'headache_severe',
        'blurred_vision',
        'chest_pain',
        'shortness_breath',
        'dizziness',
        'palpitations',
      ]);
      expect(prefills['hasSymptoms'], 'Yes');
      expect(prefills['ncdSymptoms'], [
        '10',
        '5',
        '8',
        '1',
        '2',
        '7',
      ]);
    });

    test('unmapped metabolic codes do not seed a removed checkbox option', () {
      expect(
        TriageSymptomMapper.prefillsFor('ncd', [
          'polydipsia',
          'numbness',
        ]),
        isEmpty,
      );
    });

    test('returns empty when no NCD-mappable codes', () {
      expect(
        TriageSymptomMapper.prefillsFor('ncd', ['cough', 'diarrhea']),
        isEmpty,
      );
    });
  });

  group('TriageSymptomMapper.prefillsFor anc', () {
    test('maps headache_severe and water_break to danger-sign ids', () {
      final prefills = TriageSymptomMapper.prefillsFor('anc', [
        'headache_severe',
        'water_break',
        'reduced_fetal_movement',
      ]);
      expect(prefills['ancDangerSigns'], [
        'headacheVision',
        'leakingFluid',
        'reducedFetalMovement',
      ]);
    });
  });
}
