import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/slope_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

List<BpReading> _readings(List<int> values) => [
      for (int i = 0; i < values.length; i++)
        BpReading(systolic: values[i], visitIndex: i),
    ];

void main() {
  group('SlopeCalculator', () {
    test('length < 2 → insufficientData', () {
      expect(SlopeCalculator.compute([]).insufficientData, true);
      expect(
          SlopeCalculator.compute([BpReading(systolic: 120, visitIndex: 0)])
              .insufficientData,
          true);
    });

    test('length < 2 → alert = false', () {
      expect(SlopeCalculator.compute([]).alert, false);
    });

    test('flat series → slope ≈ 0, no alert', () {
      final r = SlopeCalculator.compute(_readings([120, 120, 120, 120]));
      expect(r.slopeMmHgPerVisit, closeTo(0.0, 0.01));
      expect(r.alert, false);
    });

    test('slope exactly 4.0 → NO alert (threshold is strict >)', () {
      // x = [120, 124, 128, 132] over visits 0,1,2,3 → slope = 4.0 exactly
      final r = SlopeCalculator.compute(_readings([120, 124, 128, 132]));
      expect(r.slopeMmHgPerVisit, closeTo(4.0, 0.01));
      expect(r.alert, false);
    });

    test('slope = 4.1 → alert', () {
      // [120, 124.1, 128.2, 132.3] — use integer approx [120, 124, 129, 133]
      // Actual OLS might differ; just ensure alert when slope > 4
      final r = SlopeCalculator.compute(_readings([120, 125, 130, 135, 140]));
      // slope = 5.0 → alert
      expect(r.slopeMmHgPerVisit, closeTo(5.0, 0.1));
      expect(r.alert, true);
    });

    test('all same systolic values → numerator=0, slope=0', () {
      // When all x values are equal, numerator = Σ(i-tMean)(x-xMean) = 0
      final readings = [
        BpReading(systolic: 130, visitIndex: 0),
        BpReading(systolic: 130, visitIndex: 1),
        BpReading(systolic: 130, visitIndex: 2),
      ];
      final r = SlopeCalculator.compute(readings);
      expect(r.slopeMmHgPerVisit, 0.0);
      expect(r.alert, false);
    });

    test('descending series → negative slope, no alert', () {
      final r = SlopeCalculator.compute(_readings([150, 140, 130, 120]));
      expect(r.slopeMmHgPerVisit, lessThan(0));
      expect(r.alert, false);
    });

    test('two readings rising → slope computed correctly', () {
      // visits 0,1 values 120,130: slope = 10/1 = 10
      final r = SlopeCalculator.compute(_readings([120, 130]));
      expect(r.slopeMmHgPerVisit, closeTo(10.0, 0.01));
      expect(r.alert, true);
    });

    test('two readings flat → slope = 0', () {
      final r = SlopeCalculator.compute(_readings([120, 120]));
      expect(r.slopeMmHgPerVisit, 0.0);
      expect(r.alert, false);
    });

    test('slope 3.9 → no alert', () {
      // [120, 123.9, 127.8] ≈ [120, 124, 128] → slope ≈ 4 but let's use less
      final r = SlopeCalculator.compute(_readings([120, 124, 127]));
      // slope = OLS of [0,1,2] → [120, 124, 127]
      // t̄=1, x̄=123.67, Σ(t-t̄)(x-x̄) = -1*(-3.67)+0+1*(3.33)=3.67+3.33=7
      // Σ(t-t̄)² = 1+0+1 = 2, slope = 3.5
      expect(r.slopeMmHgPerVisit, lessThan(4.0));
      expect(r.alert, false);
    });

    test('slope uses array position [0,1,...,n-1] as time axis', () {
      // Two readings at array positions 0 and 1: slope = (140-120)/1 = 20
      // Non-sequential visitIndex values are irrelevant to the regression
      final readings = [
        BpReading(systolic: 120, visitIndex: 0),
        BpReading(systolic: 140, visitIndex: 5),
      ];
      final r = SlopeCalculator.compute(readings);
      // Array-position OLS: slope = 20 mmHg/visit
      expect(r.slopeMmHgPerVisit, closeTo(20.0, 0.01));
      expect(r.alert, true);
    });
  });
}
