import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/assessment_raw_normalizer.dart';

void main() {
  group('normalizeGlucoseTypeLabel', () {
    test('maps ANC fasting/random vocabulary to NCD labels', () {
      expect(normalizeGlucoseTypeLabel('fasting'), 'FBS');
      expect(normalizeGlucoseTypeLabel('random'), 'RBS');
    });

    test('maps NCD fbs/rbs vocabulary unchanged in display form', () {
      expect(normalizeGlucoseTypeLabel('fbs'), 'FBS');
      expect(normalizeGlucoseTypeLabel('rbs'), 'RBS');
    });
  });

  group('normalizeAssessmentRaw — ANC nested payloads', () {
    test('unwraps medicalHistoryPhysicalExamination BP fields', () {
      final out = normalizeAssessmentRaw({
        'assessmentDetails': {
          'medicalHistoryPhysicalExamination': {
            'bloodPressureSystolic': 148,
            'bloodPressureDiastolic': 92,
            'ancVisitNumber': '3',
          },
        },
      });

      expect(out['bp'], '148/92');
      expect(out['ancVisitNumber'], '3');
    });

    test('unwraps pointOfCareInvestigations fasting glucose with ANC type', () {
      final out = normalizeAssessmentRaw({
        'assessmentDetails': {
          'pointOfCareInvestigations': {
            'bloodSugar': 'fasting',
            'bloodSugarFasting': 5.8,
          },
        },
      });

      expect(out['bg'], '5.8');
      expect(out['bgType'], 'FBS');
    });

    test('unwraps pointOfCareInvestigations random glucose', () {
      final out = normalizeAssessmentRaw({
        'assessmentDetails': {
          'pointOfCareInvestigations': {
            'bloodSugar': 'random',
            'bloodSugarRandom': 9.2,
          },
        },
      });

      expect(out['bg'], '9.2');
      expect(out['bgType'], 'RBS');
    });
  });

  group('normalizeAssessmentRaw — NCD nested payloads', () {
    test('maps glucoseLog fbs/rbs to canonical bg + bgType', () {
      final out = normalizeAssessmentRaw({
        'bpLog': {'avgSystolic': 150, 'avgDiastolic': 95},
        'glucoseLog': {'glucose': 8.2, 'glucoseType': 'fbs'},
      });

      expect(out['bp'], '150/95');
      expect(out['bg'], '8.2');
      expect(out['bgType'], 'FBS');
    });
  });

  group('isGlucoseElevated', () {
    test('uses ANC GDM thresholds with normalised type labels', () {
      expect(isGlucoseElevated(5.1, 'fasting', anc: true), isTrue);
      expect(isGlucoseElevated(5.0, 'fasting', anc: true), isFalse);
      expect(isGlucoseElevated(8.5, 'random', anc: true), isTrue);
      expect(isGlucoseElevated(8.4, 'rbs', anc: true), isFalse);
    });

    test('uses NCD thresholds with normalised type labels', () {
      expect(isGlucoseElevated(7.0, 'fbs', anc: false), isTrue);
      expect(isGlucoseElevated(11.1, 'random', anc: false), isTrue);
      expect(isGlucoseElevated(6.9, 'fasting', anc: false), isFalse);
    });
  });
}
