/// FINDRISC — Finnish Diabetes Risk Score.
///
/// Validated no-lab screening tool for Type 2 DM risk (WHO-endorsed).
/// Source: Lindstrom & Tuomilehto 2003, MDCalc reference implementation.
///
/// Score 0–26 (partial when waist absent). Alert threshold ≥ 12.
library;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class FindriscCalculator {
  FindriscCalculator._();

  // ── Alert threshold ────────────────────────────────────────────────────────
  static const int _triggerScore = 12;

  // ── Pure compute ──────────────────────────────────────────────────────────

  static FindriscResult compute(CdssPatientProfile p) {
    int score = 0;

    // Age points
    if (p.ageYears >= 65) {
      score += 4;
    } else if (p.ageYears >= 55) {
      score += 3;
    } else if (p.ageYears >= 45) {
      score += 2;
    }

    // BMI points
    if (p.bmi != null) {
      if (p.bmi! >= 30) {
        score += 3;
      } else if (p.bmi! >= 25) {
        score += 1;
      }
    }

    // Waist circumference (sex-stratified)
    bool waistOmitted = false;
    if (p.waistCm == null) {
      waistOmitted = true;
    } else if (p.isFemale) {
      // Female thresholds
      if (p.waistCm! >= 89) {
        score += 4;
      } else if (p.waistCm! >= 80) {
        score += 3;
      }
    } else {
      // Male thresholds
      if (p.waistCm! >= 103) {
        score += 4;
      } else if (p.waistCm! >= 94) {
        score += 3;
      }
    }

    // Physical activity (< 30 min/day = inactive = +2)
    if (!p.isPhysicallyActive) score += 2;

    // Daily vegetables/fruit (No = +1)
    if (!p.eatsDailyFruitVeg) score += 1;

    // BP-lowering medication (Yes = +2)
    if (p.onBpMedication) score += 2;

    // Previous high blood glucose (Yes = +5)
    if (p.hadPreviousHighGlucose) score += 5;

    // Family history of diabetes (Yes = +5)
    if (p.hasFamilyHistoryDm) score += 5;

    return FindriscResult(
      score: score,
      riskLevel: _riskLevel(score),
      riskPct: _riskPct(score),
      trigger: score >= _triggerScore,
      waistOmitted: waistOmitted,
    );
  }

  // ── Risk band tables (spec §1.2) ───────────────────────────────────────────

  static String _riskLevel(int score) {
    if (score >= 21) return 'very_high';
    if (score >= 15) return 'high';
    if (score >= 12) return 'moderate';
    if (score >= 7) return 'slightly_elevated';
    return 'low';
  }

  static double _riskPct(int score) {
    if (score >= 21) return 50.0;
    if (score >= 15) return 33.0;
    if (score >= 12) return 17.0;
    if (score >= 7) return 4.0;
    return 1.0;
  }
}
