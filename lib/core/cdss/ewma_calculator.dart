/// EWMA — Exponentially Weighted Moving Average for BP trend detection.
///
/// Gives higher weight to recent BP readings (λ = 0.2). Responds faster than
/// CUSUM to sudden shifts. UCL = μ₀ + 3σ√(λ/(2−λ)) ≈ μ₀ + 14.1.
/// Requires ≥ 2 readings.
library;

import 'dart:math' as math;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class EwmaCalculator {
  EwmaCalculator._();

  static const double _lambda = 0.2;
  static const double _sigma = 10.0; // assumed population SD (mmHg)

  static EwmaResult compute(List<BpReading> readings) {
    if (readings.length < 2) {
      return const EwmaResult(
          insufficientData: true, alert: false, ewmaValue: 0, ucl: 0);
    }

    final mu0 = readings.first.systolic.toDouble();
    final ucl =
        mu0 + 3 * _sigma * math.sqrt(_lambda / (2 - _lambda));

    double ewma = mu0;
    for (int i = 1; i < readings.length; i++) {
      ewma = _lambda * readings[i].systolic + (1 - _lambda) * ewma;
    }

    return EwmaResult(
      insufficientData: false,
      alert: ewma > ucl,
      ewmaValue: ewma,
      ucl: ucl,
    );
  }
}
