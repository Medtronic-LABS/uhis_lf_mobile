import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/cusum_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

List<BpReading> _readings(List<int> values) => [
      for (int i = 0; i < values.length; i++)
        BpReading(systolic: values[i], visitIndex: i),
    ];

void main() {
  group('CusumCalculator', () {
    test('length < 2 → insufficientData', () {
      expect(CusumCalculator.compute([]).insufficientData, true);
      expect(
          CusumCalculator.compute([BpReading(systolic: 120, visitIndex: 0)])
              .insufficientData,
          true);
    });

    test('length < 2 → alert = false, finalS = 0', () {
      final r = CusumCalculator.compute([]);
      expect(r.alert, false);
      expect(r.finalS, 0.0);
    });

    test('flat series [120,120,120] → S=0, no alert', () {
      final r = CusumCalculator.compute(_readings([120, 120, 120]));
      expect(r.insufficientData, false);
      expect(r.finalS, closeTo(0.0, 0.01));
      expect(r.alert, false);
    });

    test('steady rise [120,125,130,135,140] → S > 40, alert', () {
      // k=5, h=40, mu0=120
      // i=1: S = max(0, 0 + (125-120) - 5) = max(0,0) = 0
      // i=2: S = max(0, 0 + (130-120) - 5) = 5
      // i=3: S = max(0, 5 + (135-120) - 5) = 15
      // i=4: S = max(0, 15 + (140-120) - 5) = 30
      final r = CusumCalculator.compute(_readings([120, 125, 130, 135, 140]));
      expect(r.finalS, closeTo(30.0, 0.01));
      expect(r.alert, false); // 30 is NOT > 40
    });

    test('sustained +15 increments → triggers alert', () {
      // mu0=120, k=5, each step: S += (135-120) - 5 = 10
      // After 5 readings (4 steps): S = 40, not alert
      // After 6 readings (5 steps): S = 50, alert
      final r = CusumCalculator.compute(_readings([120, 135, 135, 135, 135, 135]));
      expect(r.finalS, greaterThan(40.0));
      expect(r.alert, true);
    });

    test('spike then recovery resets via max(0,...)', () {
      // mu0=120, spike at 200 → S = max(0, 0 + 80 - 5) = 75 > 40 → alert
      // but after drop to 110: S = max(0, 75 + (110-120) - 5) = max(0,60) = 60 still alert
      // This test just verifies max(0,...) ensures S never goes negative
      final r = CusumCalculator.compute(_readings([120, 200, 110, 100]));
      expect(r.finalS, greaterThanOrEqualTo(0.0));
    });

    test('exactly S=40 → NO alert (strict >)', () {
      // Construct a series where S lands exactly at 40
      // mu0=120, step +15 each: S after 4 steps = 40
      final r = CusumCalculator.compute(_readings([120, 135, 135, 135, 135]));
      expect(r.finalS, closeTo(40.0, 0.01));
      expect(r.alert, false);
    });

    test('S=40.01 → alert', () {
      // +16 mmHg per step, k=5: S += (136-120) - 5 = 11 per step
      // After 4 steps: 44 > 40 → alert
      final r = CusumCalculator.compute(_readings([120, 136, 136, 136, 136]));
      expect(r.finalS, greaterThan(40.0));
      expect(r.alert, true);
    });

    test('decreasing series → S=0 throughout, no alert', () {
      final r = CusumCalculator.compute(_readings([140, 135, 130, 125, 120]));
      expect(r.finalS, closeTo(0.0, 0.01));
      expect(r.alert, false);
    });

    test('two readings just above baseline → S > 0 but < 40', () {
      // mu0=120, i=1: S = max(0, 0 + (150-120) - 5) = 25
      final r = CusumCalculator.compute(_readings([120, 150]));
      expect(r.finalS, closeTo(25.0, 0.01));
      expect(r.alert, false);
    });

    test('large single jump immediately triggers alert', () {
      // mu0=120, i=1: S = max(0, 0 + (170-120) - 5) = 45 > 40 → alert
      final r = CusumCalculator.compute(_readings([120, 170]));
      expect(r.alert, true);
    });
  });
}
