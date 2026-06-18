/// miniPIERS — Community Pre-Eclampsia Risk Model.
///
/// Community-adapted logistic regression based on von Dadelszen et al.
/// Validated in South Asian settings; no laboratory inputs at point of care.
///
/// Alert thresholds: ≥ 25% → RMNCH trigger + teleconsult;
///                   ≥ 50% → immediate facility referral.
library;

import 'dart:math' as math;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class MiniPiersCalculator {
  MiniPiersCalculator._();

  static const double _triggerPct = 25.0;
  static const double _criticalPct = 50.0;

  static MiniPiersResult compute(MaternalProfile p) {
    if (p.gestationalWeeks == null || p.systolicBp == null) {
      return const MiniPiersResult(
        insufficientData: true,
        riskPct: 0,
        trigger: false,
        critical: false,
      );
    }

    final lp = -8.0 +
        0.016 * p.gestationalWeeks! +
        0.065 * p.systolicBp! +
        0.8 * p.proteinuriaGrade.toDouble() +
        (p.hasHeadache ? 1.2 : 0.0) +
        (p.hasChestPain ? 1.5 : 0.0);

    final riskPct = 100.0 / (1.0 + math.exp(-lp));

    return MiniPiersResult(
      insufficientData: false,
      riskPct: riskPct,
      trigger: riskPct >= _triggerPct,
      critical: riskPct >= _criticalPct,
    );
  }
}
