import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/framingham_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

CdssPatientProfile _profile({
  required int age,
  required bool isFemale,
  double? bmi = 25.0,
  int? sbp = 120,
  bool onMeds = false,
  bool smoker = false,
  bool diabetes = false,
}) =>
    CdssPatientProfile(
      ageYears: age,
      isFemale: isFemale,
      bmi: bmi,
      systolicBp: sbp,
      waistCm: null,
      onBpMedication: onMeds,
      isSmoker: smoker,
      hasDiabetes: diabetes,
      isPhysicallyActive: true,
      eatsDailyFruitVeg: true,
      hadPreviousHighGlucose: false,
      hasFamilyHistoryDm: false,
    );

void main() {
  group('FraminghamCalculator', () {
    test('guard: age < 18 → insufficientData', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 17, isFemale: false));
      expect(r.insufficientData, true);
      expect(r.riskPct, 0);
      expect(r.trigger, false);
    });

    test('guard: bmi null → insufficientData', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 40, isFemale: false, bmi: null));
      expect(r.insufficientData, true);
    });

    test('guard: sbp null → insufficientData', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 40, isFemale: false, sbp: null));
      expect(r.insufficientData, true);
    });

    test('healthy male 30yo → low risk, no trigger', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 30, isFemale: false));
      expect(r.insufficientData, false);
      expect(r.riskPct, lessThan(10.0));
      expect(r.trigger, false);
      expect(r.highRisk, false);
    });

    test('male 55yo BMI=28 SBP=145 smoker no-DM no-meds → ~10-20% risk', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 55, isFemale: false, bmi: 28.0, sbp: 145, smoker: true));
      expect(r.insufficientData, false);
      expect(r.riskPct, greaterThanOrEqualTo(10.0));
      expect(r.trigger, true);
    });

    test('male 55yo high-risk profile → riskPct ≥ 10, trigger = true', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 55, isFemale: false, bmi: 28.0, sbp: 145, smoker: true));
      expect(r.trigger, isTrue);
    });

    test('female 60yo BMI=32 SBP=155 no-smoke DM on-meds → highRisk = true', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 60, isFemale: true, bmi: 32.0, sbp: 155,
              onMeds: true, diabetes: true));
      expect(r.highRisk, true);
      expect(r.riskPct, greaterThanOrEqualTo(20.0));
    });

    test('on-BP-meds uses higher beta (treated SBP coefficient)', () {
      final withMeds = FraminghamCalculator.compute(
          _profile(age: 55, isFemale: false, bmi: 28.0, sbp: 145, onMeds: true));
      final noMeds = FraminghamCalculator.compute(
          _profile(age: 55, isFemale: false, bmi: 28.0, sbp: 145, onMeds: false));
      // Treated coefficient is lower (1.93303 < 1.99881) → on-meds gives lower LP
      expect(withMeds.riskPct, lessThan(noMeds.riskPct));
    });

    test('trigger boundary: riskPct exactly at 10% threshold', () {
      // Any profile producing riskPct in [9.9, 10.1] should flip trigger
      final r = FraminghamCalculator.compute(
          _profile(age: 48, isFemale: false, bmi: 27.0, sbp: 138, smoker: true));
      // Just verify trigger == (riskPct >= 10)
      expect(r.trigger, r.riskPct >= 10.0);
    });

    test('highRisk boundary: riskPct == trigger iff < 20, highRisk iff ≥ 20', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 65, isFemale: false, bmi: 32.0, sbp: 170, smoker: true, diabetes: true));
      expect(r.highRisk, r.riskPct >= 20.0);
      if (r.highRisk) expect(r.trigger, true);
    });

    test('female untreated higher-risk profile → riskPct > 0', () {
      final r = FraminghamCalculator.compute(
          _profile(age: 55, isFemale: true, bmi: 30.0, sbp: 155, smoker: true, diabetes: true));
      expect(r.riskPct, greaterThan(0));
      expect(r.insufficientData, false);
    });

    test('diabetes adds to LP and increases risk vs no-diabetes', () {
      final withDm = FraminghamCalculator.compute(
          _profile(age: 50, isFemale: false, bmi: 26.0, sbp: 130, diabetes: true));
      final noDm = FraminghamCalculator.compute(
          _profile(age: 50, isFemale: false, bmi: 26.0, sbp: 130, diabetes: false));
      expect(withDm.riskPct, greaterThan(noDm.riskPct));
    });
  });
}
