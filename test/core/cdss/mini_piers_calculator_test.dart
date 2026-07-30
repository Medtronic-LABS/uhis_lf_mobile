import 'package:flutter_test/flutter_test.dart';
import 'package:uhis_next/core/cdss/mini_piers_calculator.dart';
import 'package:uhis_next/core/cdss/models/cdss_inputs.dart';

MaternalProfile _profile({
  int? ga,
  int? sbp,
  int proteinuria = 0,
  bool headache = false,
  bool chestPain = false,
}) =>
    MaternalProfile(
      gestationalWeeks: ga,
      systolicBp: sbp,
      proteinuriaGrade: proteinuria,
      hasHeadache: headache,
      hasChestPain: chestPain,
    );

void main() {
  group('MiniPiersCalculator', () {
    test('null gestationalWeeks → insufficientData', () {
      final r = MiniPiersCalculator.compute(_profile(sbp: 120));
      expect(r.insufficientData, true);
      expect(r.trigger, false);
      expect(r.critical, false);
    });

    test('null sbp → insufficientData', () {
      final r = MiniPiersCalculator.compute(_profile(ga: 28));
      expect(r.insufficientData, true);
    });

    test('both null → insufficientData', () {
      expect(MiniPiersCalculator.compute(_profile()).insufficientData, true);
    });

    // miniPIERS is calibrated for hypertensive patients.
    // LP = -8 + 0.016*GA + 0.065*SBP + 0.8*grade + symptoms.
    // With SBP=100, GA=10: LP = -8 + 0.16 + 6.5 = -1.34 → risk ≈ 20.7%
    test('below-threshold: GA=10 SBP=100 grade=0 → risk < 25%, no trigger', () {
      final r = MiniPiersCalculator.compute(
          _profile(ga: 10, sbp: 100, proteinuria: 0));
      expect(r.insufficientData, false);
      expect(r.riskPct, lessThan(25.0));
      expect(r.trigger, false);
      expect(r.critical, false);
    });

    // GA=28, SBP=103: LP ≈ -0.857 → risk ≈ 29.8% — triggers but not critical
    test('trigger not critical: GA=28 SBP=103 grade=0 → 25-50%', () {
      final r = MiniPiersCalculator.compute(
          _profile(ga: 28, sbp: 103, proteinuria: 0));
      expect(r.riskPct, inInclusiveRange(25.0, 50.0));
      expect(r.trigger, true);
      expect(r.critical, false);
    });

    // GA=28, SBP=120: LP ≈ 0.248 → risk ≈ 56% — critical
    test('critical: GA=28 SBP=120 grade=0 → ≥50%', () {
      final r = MiniPiersCalculator.compute(
          _profile(ga: 28, sbp: 120, proteinuria: 0));
      expect(r.riskPct, greaterThanOrEqualTo(50.0));
      expect(r.critical, true);
      expect(r.trigger, true);
    });

    // High-SBP + symptoms → very high risk
    test('critical: GA=36 SBP=165 grade=3 headache+chest → ≥50%', () {
      final r = MiniPiersCalculator.compute(
          _profile(ga: 36, sbp: 165, proteinuria: 3, headache: true, chestPain: true));
      expect(r.riskPct, greaterThanOrEqualTo(50.0));
      expect(r.critical, true);
    });

    test('trigger boundary: trigger == (riskPct >= 25)', () {
      final r = MiniPiersCalculator.compute(_profile(ga: 15, sbp: 103));
      expect(r.trigger, r.riskPct >= 25.0);
    });

    test('critical boundary: critical == (riskPct >= 50)', () {
      final r = MiniPiersCalculator.compute(_profile(ga: 28, sbp: 115));
      expect(r.critical, r.riskPct >= 50.0);
    });

    test('LP formula: manual check GA=20 SBP=120 grade=0', () {
      // lp = -8 + 0.016*20 + 0.065*120 = -8 + 0.32 + 7.8 = 0.12
      // risk ≈ 53%
      final r = MiniPiersCalculator.compute(
          _profile(ga: 20, sbp: 120, proteinuria: 0));
      expect(r.riskPct, closeTo(53.0, 2.0));
    });

    test('headache adds 1.2 to LP → increases risk', () {
      final noSx = MiniPiersCalculator.compute(_profile(ga: 20, sbp: 120));
      final withHa = MiniPiersCalculator.compute(
          _profile(ga: 20, sbp: 120, headache: true));
      expect(withHa.riskPct, greaterThan(noSx.riskPct));
    });

    test('chest pain adds 1.5 to LP → increases risk more than headache alone', () {
      final withHa = MiniPiersCalculator.compute(
          _profile(ga: 20, sbp: 120, headache: true));
      final withCp = MiniPiersCalculator.compute(
          _profile(ga: 20, sbp: 120, chestPain: true));
      expect(withCp.riskPct, greaterThan(withHa.riskPct));
    });

    test('proteinuria grade increases risk monotonically', () {
      final grade0 = MiniPiersCalculator.compute(_profile(ga: 20, sbp: 110, proteinuria: 0));
      final grade1 = MiniPiersCalculator.compute(_profile(ga: 20, sbp: 110, proteinuria: 1));
      final grade2 = MiniPiersCalculator.compute(_profile(ga: 20, sbp: 110, proteinuria: 2));
      expect(grade1.riskPct, greaterThan(grade0.riskPct));
      expect(grade2.riskPct, greaterThan(grade1.riskPct));
    });
  });
}
