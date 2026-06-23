/// CDSS Engine — orchestrates all six clinical scoring algorithms.
///
/// Pure Dart. No I/O. Accepts pre-fetched data from the caller (ViewModel or
/// use-case layer) and returns [CdssEngineOutput]. Each algorithm is run only
/// when its required inputs are available; missing inputs yield null fields on
/// the output, never exceptions.
library;

import 'cusum_calculator.dart';
import 'ewma_calculator.dart';
import 'findrisc_calculator.dart';
import 'framingham_calculator.dart';
import 'mini_piers_calculator.dart';
import 'models/cdss_inputs.dart';
import 'models/cdss_results.dart';
import 'slope_calculator.dart';

class CdssEngine {
  CdssEngine._();

  /// Run all applicable algorithms and return a unified output.
  ///
  /// - [profile]   — required; must not be null.
  /// - [bpHistory] — prior systolic BP readings, oldest first (visitIndex=0).
  ///   Trend algorithms (CUSUM/EWMA/Slope) require at least 2 readings.
  /// - [maternal]  — optional; only passed for pregnant patients.
  ///   miniPIERS is skipped when null.
  static CdssEngineOutput evaluate({
    required CdssPatientProfile profile,
    required List<BpReading> bpHistory,
    MaternalProfile? maternal,
  }) {
    // FINDRISC — always run; partial result if waist absent
    final findrisc = FindriscCalculator.compute(profile);

    // Framingham — only when age ≥ 18, BMI and SBP available
    final framingham =
        (profile.ageYears >= 18 &&
                profile.bmi != null &&
                profile.systolicBp != null)
            ? FraminghamCalculator.compute(profile)
            : null;

    // Trend algorithms — only when ≥ 2 prior readings exist
    final hasTrendData = bpHistory.length >= 2;
    final cusum = hasTrendData ? CusumCalculator.compute(bpHistory) : null;
    final ewma = hasTrendData ? EwmaCalculator.compute(bpHistory) : null;
    final slope = hasTrendData ? SlopeCalculator.compute(bpHistory) : null;

    // miniPIERS — only for pregnant patients
    final miniPiers =
        maternal != null ? MiniPiersCalculator.compute(maternal) : null;

    return CdssEngineOutput(
      findrisc: findrisc,
      framingham: framingham,
      cusum: cusum,
      ewma: ewma,
      slope: slope,
      miniPiers: miniPiers,
    );
  }
}
