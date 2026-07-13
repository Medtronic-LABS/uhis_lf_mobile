/// Classification result for a vital sign reading.
enum VitalClassification {
  normal,
  low,
  high,
  critical;

  String get label {
    switch (this) {
      case VitalClassification.normal:
        return 'Normal';
      case VitalClassification.low:
        return 'Low';
      case VitalClassification.high:
        return 'High';
      case VitalClassification.critical:
        return 'Critical';
    }
  }
}

/// Pure-function vital sign classifier.
///
/// Age-aware thresholds for pediatric vitals (IMCI).
class VitalClassifier {
  VitalClassifier._();

  /// Classify a vital sign value.
  static VitalClassification? classify(
    String code,
    double value, {
    int? patientAge,
  }) {
    switch (code) {
      case 'temperature':
        return _classifyTemperature(value);
      case 'respiratory_rate':
        return _classifyRespiratoryRate(value, patientAge);
      case 'spo2':
        return _classifySpO2(value);
      case 'weight':
        return null; // Weight doesn't have normal/abnormal classification
      case 'height':
        return null;
      case 'muac':
        return _classifyMuac(value, patientAge);
      case 'glucose':
        return _classifyGlucose(value);
      case 'fundal_height':
        return null; // Needs gestational age for classification
      case 'fetal_heart_rate':
        return _classifyFetalHeartRate(value);
      default:
        return null;
    }
  }

  /// Classify blood pressure.
  static VitalClassification classifyBp(double systolic, double diastolic) {
    // Critical hypertension — crisis threshold matches AssessmentDefinedParams (110 diastolic, not 120)
    if (systolic >= 180 || diastolic >= 110) {
      return VitalClassification.critical;
    }
    // Severe hypertension
    if (systolic >= 160 || diastolic >= 100) {
      return VitalClassification.high;
    }
    // Hypertension
    if (systolic >= 140 || diastolic >= 90) {
      return VitalClassification.high;
    }
    // Hypotension
    if (systolic < 90 || diastolic < 60) {
      return VitalClassification.low;
    }
    // Normal
    return VitalClassification.normal;
  }

  /// Classify temperature (°C).
  static VitalClassification _classifyTemperature(double temp) {
    if (temp >= 39.0) return VitalClassification.critical; // High fever
    if (temp >= 37.5) return VitalClassification.high; // Fever
    if (temp < 35.5) return VitalClassification.low; // Hypothermia
    return VitalClassification.normal;
  }

  /// Classify respiratory rate (breaths/min) — age-aware.
  ///
  /// WHO IMCI thresholds:
  /// - Under 2 months: fast breathing = 60+ bpm
  /// - 2-12 months: fast breathing = 50+ bpm
  /// - 1-5 years: fast breathing = 40+ bpm
  /// - Over 5: adult thresholds (12-20 normal)
  static VitalClassification _classifyRespiratoryRate(double rr, int? age) {
    // Critical for all ages
    if (rr < 10) return VitalClassification.critical;
    if (rr >= 70) return VitalClassification.critical;

    // Age-specific thresholds
    if (age != null) {
      if (age < 1) {
        // Under 1 year (in months — but we have years, so under 1)
        // Approximate: under 2 months = very young infant
        if (rr >= 60) return VitalClassification.high;
        if (rr < 30) return VitalClassification.low;
      } else if (age < 5) {
        // 1-5 years
        if (rr >= 40) return VitalClassification.high;
        if (rr < 20) return VitalClassification.low;
      } else {
        // Over 5 years / adult
        if (rr >= 24) return VitalClassification.high;
        if (rr < 12) return VitalClassification.low;
      }
    } else {
      // No age — use adult thresholds
      if (rr >= 24) return VitalClassification.high;
      if (rr < 12) return VitalClassification.low;
    }

    return VitalClassification.normal;
  }

  /// Classify SpO2 (oxygen saturation %).
  static VitalClassification _classifySpO2(double spo2) {
    if (spo2 < 90) return VitalClassification.critical;
    if (spo2 < 94) return VitalClassification.low;
    return VitalClassification.normal;
  }

  /// Classify MUAC (mid-upper arm circumference) — for children 6mo-5yr.
  ///
  /// WHO thresholds:
  /// - <11.5 cm: Severe acute malnutrition (SAM)
  /// - 11.5-12.5 cm: Moderate acute malnutrition (MAM)
  /// - >12.5 cm: Normal
  static VitalClassification _classifyMuac(double muac, int? age) {
    if (muac < 11.5) return VitalClassification.critical; // SAM
    if (muac < 12.5) return VitalClassification.low; // MAM
    return VitalClassification.normal;
  }

  /// Classify blood glucose (mmol/L).
  ///
  /// Thresholds from NCDReferralColorEvaluator + AssessmentDefinedParams:
  /// - <3.9: Hypoglycaemia (critical)
  /// - >27.8: Crisis hyperglycaemia (critical)
  /// - >11.1: Uncontrolled / PNC urgent (high)
  /// - >7.8: Above RBS screening normal (elevated)
  static VitalClassification _classifyGlucose(double glucose) {
    if (glucose < 3.9) return VitalClassification.critical; // Hypoglycaemia
    if (glucose > 27.8) return VitalClassification.critical; // Crisis hyperglycaemia
    if (glucose > 11.1) return VitalClassification.high; // NCD uncontrolled / PNC urgent
    if (glucose > 7.8) return VitalClassification.low; // Above RBS screening normal
    return VitalClassification.normal;
  }

  /// Classify fetal heart rate (bpm).
  ///
  /// Normal range: 110-160 bpm
  static VitalClassification _classifyFetalHeartRate(double fhr) {
    if (fhr < 100 || fhr > 180) return VitalClassification.critical;
    if (fhr < 110 || fhr > 160) return VitalClassification.high;
    return VitalClassification.normal;
  }
}
