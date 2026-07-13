/// NCD patient status — controlled / uncontrolled gate.
///
/// Equivalent to Android's PatientStatusEvaluator.
/// Thresholds from assessment_thresholds.dart.
library;

import 'assessment_thresholds.dart';

enum NcdStatus { controlled, uncontrolled, unknown }

class NcdPatientStatusEvaluator {
  NcdPatientStatusEvaluator._();

  /// Returns [NcdStatus.unknown] when no readings are provided.
  ///
  /// Uncontrolled if ANY of:
  ///   - systolic ≥ 141
  ///   - diastolic ≥ 91
  ///   - FBS ≥ 7.1 mmol/L
  ///   - RBS ≥ 11.1 mmol/L
  ///   - comorbidities present
  ///   - complications present
  ///   - not on medication
  ///
  /// Controlled requires ALL vitals within bounds + medication confirmed.
  static NcdStatus evaluate({
    double? systolic,
    double? diastolic,
    double? fastingGlucoseMmol,
    double? randomGlucoseMmol,
    bool? onMedication,
    bool? hasComorbidities,
    bool? hasComplications,
  }) {
    if (systolic == null &&
        diastolic == null &&
        fastingGlucoseMmol == null &&
        randomGlucoseMmol == null) {
      return NcdStatus.unknown;
    }

    if (systolic != null && systolic >= ncdUncontrolledSystolic) {
      return NcdStatus.uncontrolled;
    }
    if (diastolic != null && diastolic >= ncdUncontrolledDiastolic) {
      return NcdStatus.uncontrolled;
    }
    if (fastingGlucoseMmol != null && fastingGlucoseMmol >= ncdUncontrolledFbs) {
      return NcdStatus.uncontrolled;
    }
    if (randomGlucoseMmol != null && randomGlucoseMmol >= ncdUncontrolledRbs) {
      return NcdStatus.uncontrolled;
    }
    if (hasComorbidities == true) return NcdStatus.uncontrolled;
    if (hasComplications == true) return NcdStatus.uncontrolled;
    if (onMedication == false) return NcdStatus.uncontrolled;

    return NcdStatus.controlled;
  }

  /// Whether the patient meets the controlled threshold for BP alone.
  static bool isBpControlled(double systolic, double diastolic) =>
      systolic <= bpHighSystolic && diastolic <= bpHighDiastolic;

  /// Whether the patient meets the controlled threshold for glucose alone.
  static bool isGlucoseControlled({
    double? fastingMmol,
    double? randomMmol,
  }) {
    if (fastingMmol != null && fastingMmol >= ncdUncontrolledFbs) return false;
    if (randomMmol != null && randomMmol >= ncdUncontrolledRbs) return false;
    return true;
  }
}
