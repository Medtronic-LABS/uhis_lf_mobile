/// Framingham No-Lab CVD Risk — D'Agostino 2008 office model.
///
/// Sex-stratified logistic regression for 10-year CVD risk using no laboratory
/// values. Source: D'Agostino et al., Circulation 2008.
///
/// Alert thresholds: ≥ 10% → trigger NCD; ≥ 20% → high risk, urgent review.
library;

import 'dart:math' as math;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class FraminghamCalculator {
  FraminghamCalculator._();

  // ── Coefficients (D'Agostino 2008) ────────────────────────────────────────

  // Male model
  static const double _mAgeLn = 3.06117;
  static const double _mBmiLn = 1.12370;
  static const double _mSbpLnTreated = 1.93303;
  static const double _mSbpLnUntreated = 1.99881;
  static const double _mSmoking = 0.65451;
  static const double _mDiabetes = 0.57367;
  static const double _mBaselineSurvival = 0.88936;
  static const double _mMeanCoeff = 23.9388;

  // Female model
  static const double _fAgeLn = 2.32888;
  static const double _fBmiLn = 1.20904;
  static const double _fSbpLnTreated = 2.76157;
  static const double _fSbpLnUntreated = 2.82263;
  static const double _fSmoking = 0.52873;
  static const double _fDiabetes = 0.69154;
  static const double _fBaselineSurvival = 0.94833;
  static const double _fMeanCoeff = 26.1931;

  // ── Alert thresholds ───────────────────────────────────────────────────────
  static const double _triggerPct = 10.0;
  static const double _highRiskPct = 20.0;

  // ── Pure compute ──────────────────────────────────────────────────────────

  static FraminghamResult compute(CdssPatientProfile p) {
    if (p.ageYears < 18 || p.bmi == null || p.systolicBp == null) {
      return const FraminghamResult(
        riskPct: 0,
        trigger: false,
        highRisk: false,
        insufficientData: true,
      );
    }

    final age = p.ageYears.toDouble();
    final bmi = p.bmi!;
    final sbp = p.systolicBp!.toDouble();
    final smoking = p.isSmoker ? 1.0 : 0.0;
    final diabetes = p.hasDiabetes ? 1.0 : 0.0;

    double lp;
    double baselineSurvival;
    double meanCoeff;

    if (!p.isFemale) {
      // Male
      final betaSbp =
          p.onBpMedication ? _mSbpLnTreated : _mSbpLnUntreated;
      lp = _mAgeLn * math.log(age) +
          _mBmiLn * math.log(bmi) +
          betaSbp * math.log(sbp) +
          _mSmoking * smoking +
          _mDiabetes * diabetes;
      baselineSurvival = _mBaselineSurvival;
      meanCoeff = _mMeanCoeff;
    } else {
      // Female
      final betaSbp =
          p.onBpMedication ? _fSbpLnTreated : _fSbpLnUntreated;
      lp = _fAgeLn * math.log(age) +
          _fBmiLn * math.log(bmi) +
          betaSbp * math.log(sbp) +
          _fSmoking * smoking +
          _fDiabetes * diabetes;
      baselineSurvival = _fBaselineSurvival;
      meanCoeff = _fMeanCoeff;
    }

    final risk =
        (1.0 - math.pow(baselineSurvival, math.exp(lp - meanCoeff))) * 100.0;
    final riskPct = risk.clamp(0.0, 99.9);

    return FraminghamResult(
      riskPct: riskPct,
      trigger: riskPct >= _triggerPct,
      highRisk: riskPct >= _highRiskPct,
    );
  }
}
