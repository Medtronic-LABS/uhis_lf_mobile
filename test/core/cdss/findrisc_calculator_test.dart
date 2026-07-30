import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/findrisc_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

CdssPatientProfile _male({
  int age = 30,
  double? bmi = 22.0,
  double? waist = 85.0,
  bool active = true,
  bool eatsFruitVeg = true,
  bool bpMeds = false,
  bool prevGlucose = false,
  bool familyDm = false,
}) =>
    CdssPatientProfile(
      ageYears: age,
      isFemale: false,
      bmi: bmi,
      systolicBp: 120,
      waistCm: waist,
      onBpMedication: bpMeds,
      isSmoker: false,
      hasDiabetes: false,
      isPhysicallyActive: active,
      eatsDailyFruitVeg: eatsFruitVeg,
      hadPreviousHighGlucose: prevGlucose,
      hasFamilyHistoryDm: familyDm,
    );

CdssPatientProfile _female({
  int age = 30,
  double? bmi = 22.0,
  double? waist = 70.0,
  bool active = true,
  bool eatsFruitVeg = true,
}) =>
    CdssPatientProfile(
      ageYears: age,
      isFemale: true,
      bmi: bmi,
      systolicBp: 120,
      waistCm: waist,
      onBpMedication: false,
      isSmoker: false,
      hasDiabetes: false,
      isPhysicallyActive: active,
      eatsDailyFruitVeg: eatsFruitVeg,
      hadPreviousHighGlucose: false,
      hasFamilyHistoryDm: false,
    );

void main() {
  group('FindriscCalculator', () {
    test('score=0 for all low-risk male', () {
      final r = FindriscCalculator.compute(_male());
      expect(r.score, 0);
      expect(r.trigger, false);
      expect(r.waistOmitted, false);
    });

    test('score=11 (below trigger) — no trigger', () {
      // age 45-54 → +2, bmi 25-29 → +1, waist male 94-102 → +3, inactive → +2, no veg → +1, no bpMeds, no prevGlucose, no familyDm
      // total = 9 with bmi+waist+age+inactive+noVeg = 2+1+3+2+1=9
      final p = _male(age: 50, bmi: 27.0, waist: 98.0, active: false, eatsFruitVeg: false);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 9);
      expect(r.trigger, false);
    });

    test('score=12 — trigger fires (moderate)', () {
      // age 55-64 → +3, bmi ≥30 → +3, waist male 94-102 → +3, inactive → +2, no veg → +1
      // = 12
      final p = _male(age: 60, bmi: 32.0, waist: 98.0, active: false, eatsFruitVeg: false);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 12);
      expect(r.trigger, true);
      expect(r.riskLevel, 'moderate');
    });

    test('score=21 — very high risk', () {
      // age ≥65→4, bmi≥30→3, waist male ≥103→4, inactive→2, noVeg→1, bpMeds→2, prevGlucose→5
      // = 21
      final p = _male(
        age: 70, bmi: 35.0, waist: 110.0, active: false,
        eatsFruitVeg: false, bpMeds: true, prevGlucose: true,
      );
      final r = FindriscCalculator.compute(p);
      expect(r.score, 21);
      expect(r.trigger, true);
      expect(r.riskLevel, 'very_high');
    });

    test('boundary: age exactly 45 → +2', () {
      final p = _male(age: 45);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 2);
    });

    test('boundary: age exactly 55 → +3', () {
      final p = _male(age: 55);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 3);
    });

    test('boundary: age exactly 65 → +4', () {
      final p = _male(age: 65);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 4);
    });

    test('null waist → waistOmitted=true, score computed without waist points', () {
      final p = _male(waist: null);
      final r = FindriscCalculator.compute(p);
      expect(r.waistOmitted, true);
      expect(r.score, 0); // no waist component, all else low-risk
    });

    test('female waist threshold: <80 → 0 points', () {
      final p = _female(waist: 79.0);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 0);
    });

    test('female waist threshold: 80-88 → +3', () {
      final p = _female(waist: 84.0);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 3);
    });

    test('female waist threshold: ≥89 → +4', () {
      final p = _female(waist: 90.0);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 4);
    });

    test('male waist threshold: <94 → 0, 94-102 → +3, ≥103 → +4', () {
      expect(FindriscCalculator.compute(_male(waist: 90.0)).score, 0);
      expect(FindriscCalculator.compute(_male(waist: 95.0)).score, 3);
      expect(FindriscCalculator.compute(_male(waist: 103.0)).score, 4);
    });

    test('family history DM → +5', () {
      final p = _male(familyDm: true);
      final r = FindriscCalculator.compute(p);
      expect(r.score, 5);
    });

    test('riskPct assigned per spec thresholds', () {
      // score < 7 → 1% (boundary value)
      expect(FindriscCalculator.compute(_male()).riskPct, lessThanOrEqualTo(1.0));
      // score ≥ 15 → ~33%
      final high = _male(age: 65, bmi: 32.0, waist: 110.0, active: false,
          eatsFruitVeg: false, bpMeds: true);
      // age≥65→4, bmi≥30→3, waist≥103→4, inactive→2, noVeg→1, bpMeds→2 = 16
      final r = FindriscCalculator.compute(high);
      expect(r.riskPct, greaterThanOrEqualTo(33.0));
    });
  });
}
