/// CUSUM — Cumulative Sum Control Chart for BP trend detection.
///
/// Detects systematic upward drift in systolic BP across visits. Fires before
/// individual readings cross the 140 mmHg threshold. Requires ≥ 2 readings.
///
/// Parameters: k = 5 mmHg (slack), h = 40 (decision interval ≈ 4σ, σ = 10).
library;

import 'dart:math' as math;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class CusumCalculator {
  CusumCalculator._();

  static const double _k = 5.0;  // allowance / slack (mmHg)
  static const double _h = 40.0; // decision interval

  static CusumResult compute(List<BpReading> readings) {
    if (readings.length < 2) {
      return const CusumResult(
          insufficientData: true, alert: false, finalS: 0);
    }

    final mu0 = readings.first.systolic.toDouble();
    double s = 0;

    for (int i = 1; i < readings.length; i++) {
      s = math.max(0, s + (readings[i].systolic - mu0) - _k);
    }

    return CusumResult(insufficientData: false, alert: s > _h, finalS: s);
  }
}
