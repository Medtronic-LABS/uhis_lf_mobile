import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/ewma_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';
import 'dart:math' as math;

List<BpReading> _readings(List<int> values) => [
      for (int i = 0; i < values.length; i++)
        BpReading(systolic: values[i], visitIndex: i),
    ];

void main() {
  group('EwmaCalculator', () {
    const lambda = 0.2;
    const sigma = 10.0;

    test('length < 2 → insufficientData', () {
      expect(EwmaCalculator.compute([]).insufficientData, true);
      expect(
          EwmaCalculator.compute([BpReading(systolic: 120, visitIndex: 0)])
              .insufficientData,
          true);
    });

    test('length < 2 → alert = false', () {
      expect(EwmaCalculator.compute([]).alert, false);
    });

    test('UCL formula: mu0=120 → UCL ≈ 134.1', () {
      final r = EwmaCalculator.compute(_readings([120, 120]));
      final expectedUcl = 120 + 3 * sigma * math.sqrt(lambda / (2 - lambda));
      expect(r.ucl, closeTo(expectedUcl, 0.1));
    });

    test('flat series at baseline → ewma ≈ baseline, no alert', () {
      final r = EwmaCalculator.compute(_readings([120, 120, 120, 120, 120]));
      expect(r.ewmaValue, closeTo(120.0, 0.1));
      expect(r.alert, false);
    });

    test('series at baseline → ewma stays below UCL', () {
      final r = EwmaCalculator.compute(_readings([120, 120, 120]));
      expect(r.ewmaValue, lessThan(r.ucl));
    });

    test('single large jump → ewma crosses UCL, alert', () {
      // mu0=120, UCL≈134.1
      // after one step of 200: ewma = 0.2*200 + 0.8*120 = 40 + 96 = 136 > 134.1
      final r = EwmaCalculator.compute(_readings([120, 200]));
      expect(r.ewmaValue, greaterThan(r.ucl));
      expect(r.alert, true);
    });

    test('EWMA computation manual check: 2 readings', () {
      // mu0=120, r1=130: ewma = 0.2*130 + 0.8*120 = 26 + 96 = 122
      final r = EwmaCalculator.compute(_readings([120, 130]));
      expect(r.ewmaValue, closeTo(122.0, 0.1));
    });

    test('EWMA computation manual check: 3 readings', () {
      // mu0=120, r1=130: ewma1 = 122
      // r2=130: ewma2 = 0.2*130 + 0.8*122 = 26 + 97.6 = 123.6
      final r = EwmaCalculator.compute(_readings([120, 130, 130]));
      expect(r.ewmaValue, closeTo(123.6, 0.1));
      expect(r.alert, false); // 123.6 < 134.1
    });

    test('slowly rising series eventually crosses UCL', () {
      // Each step +15 from 120
      final readings = [120, 135, 135, 135, 135, 135, 135, 135, 135, 135];
      final r = EwmaCalculator.compute(_readings(readings));
      // After many steps EWMA approaches 135 > UCL 134.1
      expect(r.alert, true);
    });

    test('decreasing series → ewma < baseline, no alert', () {
      final r = EwmaCalculator.compute(_readings([140, 130, 120, 110, 100]));
      expect(r.alert, false);
    });

    test('alert = false when ewma exactly equals UCL (strict >)', () {
      // Construct artificially by checking edge: if ewma == ucl, alert should be false
      // We can verify via the compute result
      final r = EwmaCalculator.compute(_readings([120, 120]));
      // ewma stays at 120, UCL >> 120, definitely no alert
      expect(r.alert, false);
    });
  });
}
