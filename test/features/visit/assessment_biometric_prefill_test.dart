import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/features/visit/assessment_repository.dart';

void main() {
  group('AssessmentRepository biometricFromMapForTest', () {
    test('reads local NCD biometric.height', () {
      expect(
        AssessmentRepository.biometricFromMapForTest({
          'biometric': {'height': 165, 'weight': 60},
        }, 'height'),
        165,
      );
    });

    test('reads nested assessmentDetails.ncd.biometric (history DTO)', () {
      expect(
        AssessmentRepository.biometricFromMapForTest({
          'assessmentDetails': {
            'ncd': {
              'biometric': {'height': 158.5, 'weight': 55},
            },
          },
        }, 'height'),
        158.5,
      );
    });

    test('reads observations-style string height with unit', () {
      expect(
        AssessmentRepository.biometricFromMapForTest({
          'height': '162 cm',
          'weight': '58 kg',
        }, 'height'),
        162,
      );
      expect(
        AssessmentRepository.biometricFromMapForTest({
          'height': '162 cm',
          'weight': '58 kg',
        }, 'weight'),
        58,
      );
    });

    test('ignores missing / non-positive values', () {
      expect(
        AssessmentRepository.biometricFromMapForTest({
          'biometric': {'height': 0},
        }, 'height'),
        isNull,
      );
      expect(
        AssessmentRepository.biometricFromMapForTest({}, 'height'),
        isNull,
      );
    });
  });
}
