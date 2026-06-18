/// Linear Slope — OLS regression on systolic BP time series.
///
/// Provides an intuitive mmHg-per-visit rate of rise. A slope > 4 mmHg/visit
/// means the patient will reach 140 mmHg within 4 visits even if today's
/// reading is 125 mmHg. Requires ≥ 2 readings.
library;

import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';

class SlopeCalculator {
  SlopeCalculator._();

  static const double _alertSlope = 4.0; // mmHg/visit

  static SlopeResult compute(List<BpReading> readings) {
    if (readings.length < 2) {
      return const SlopeResult(
          insufficientData: true, alert: false, slopeMmHgPerVisit: 0);
    }

    final n = readings.length;

    // t = [0, 1, ..., n-1] (array positions, ordered oldest→newest)
    // x = systolic values
    final tMean = (n - 1) / 2.0;
    final xMean =
        readings.fold<double>(0, (sum, r) => sum + r.systolic) / n;

    double numerator = 0;
    double denominator = 0;
    for (int i = 0; i < n; i++) {
      final dt = i - tMean;
      final dx = readings[i].systolic - xMean;
      numerator += dt * dx;
      denominator += dt * dt;
    }

    // Guard: denominator == 0 when all visit indices are identical
    final slope = denominator == 0 ? 0.0 : numerator / denominator;

    return SlopeResult(
      insufficientData: false,
      alert: slope > _alertSlope,
      slopeMmHgPerVisit: slope,
    );
  }
}
