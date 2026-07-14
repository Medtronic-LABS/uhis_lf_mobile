import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/clinical/assessment_thresholds.dart';
import 'package:uhis_next/core/clinical/referral_evaluator.dart';
import 'package:uhis_next/features/visit/models/anc_assessment.dart';

void main() {
  group('fahrenheitToCelsius', () {
    test('converts normal body temperature correctly', () {
      expect(fahrenheitToCelsius(98.6), closeTo(37.0, 0.05));
    });

    test('converts the high-fever reference point correctly', () {
      expect(fahrenheitToCelsius(102.0), closeTo(38.89, 0.01));
    });
  });

  group('AncReferralEvaluator temperature handling', () {
    test(
        'a normal 98.6°F reading, once converted, does NOT trigger a high-fever referral',
        () {
      final result = AncReferralEvaluator.evaluate(
        const AncAssessment(),
        temperatureCelsius: fahrenheitToCelsius(98.6),
      );

      expect(result.isEmergencyReferral, isFalse);
      expect(result.emergencyConditions, isNot(contains('High fever (≥102°F)')));
    });

    test(
        'passing the raw unconverted Fahrenheit value reproduces the bug '
        '(documents why the conversion is required)', () {
      final result = AncReferralEvaluator.evaluate(
        const AncAssessment(),
        temperatureCelsius: 98.6, // raw °F value, not converted — the bug
      );

      expect(result.emergencyConditions, contains('High fever (≥102°F)'));
    });

    test('a genuine high fever (103°F) still triggers emergency referral after conversion', () {
      final result = AncReferralEvaluator.evaluate(
        const AncAssessment(),
        temperatureCelsius: fahrenheitToCelsius(103.0),
      );

      expect(result.emergencyConditions, contains('High fever (≥102°F)'));
    });
  });
}
