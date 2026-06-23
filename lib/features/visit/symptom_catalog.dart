import '../../core/models/programme.dart';

/// A symptom definition for the triage checklist.
class SymptomDef {
  const SymptomDef({
    required this.code,
    required this.label,
    this.icon,
    this.programmes = const {},
    this.isDangerSign = false,
  });

  final String code;
  final String label;
  final String? icon; // Material icon name
  final Set<Programme> programmes;
  final bool isDangerSign;
}

/// Catalog of symptoms by programme.
class SymptomCatalog {
  SymptomCatalog._();

  // ── IMCI Symptoms (Under-5 children) ─────────────────────────────────────
  static const imciSymptoms = [
    SymptomDef(code: 'fever', label: 'Fever', icon: 'thermostat'),
    SymptomDef(code: 'cough', label: 'Cough', icon: 'air'),
    SymptomDef(code: 'diarrhea', label: 'Diarrhea', icon: 'water_drop'),
    SymptomDef(code: 'vomiting', label: 'Vomiting', icon: 'sick'),
    SymptomDef(code: 'not_eating', label: 'Not eating/drinking', icon: 'no_food'),
    SymptomDef(code: 'convulsions', label: 'Convulsions', icon: 'warning', isDangerSign: true),
    SymptomDef(code: 'difficulty_breathing', label: 'Difficulty breathing', icon: 'air', isDangerSign: true),
    SymptomDef(code: 'lethargy', label: 'Unusually sleepy/difficult to wake', icon: 'bedtime', isDangerSign: true),
  ];

  // ── ANC Symptoms (Pregnant women) ────────────────────────────────────────
  static const ancSymptoms = [
    SymptomDef(code: 'headache', label: 'Severe headache', icon: 'psychology'),
    SymptomDef(code: 'blurred_vision', label: 'Blurred vision', icon: 'visibility_off'),
    SymptomDef(code: 'abdominal_pain', label: 'Abdominal pain', icon: 'healing'),
    SymptomDef(code: 'vaginal_bleeding', label: 'Vaginal bleeding', icon: 'water_drop', isDangerSign: true),
    SymptomDef(code: 'swelling', label: 'Swelling (face/hands/feet)', icon: 'bubble_chart'),
    SymptomDef(code: 'fever', label: 'Fever', icon: 'thermostat'),
    SymptomDef(code: 'reduced_fetal_movement', label: 'Reduced fetal movement', icon: 'child_care', isDangerSign: true),
    SymptomDef(code: 'water_break', label: 'Water break/leaking', icon: 'water', isDangerSign: true),
  ];

  // ── NCD Symptoms (Diabetes/Hypertension) ─────────────────────────────────
  static const ncdSymptoms = [
    SymptomDef(code: 'headache', label: 'Headache', icon: 'psychology'),
    SymptomDef(code: 'dizziness', label: 'Dizziness', icon: 'blur_on'),
    SymptomDef(code: 'chest_pain', label: 'Chest pain', icon: 'favorite', isDangerSign: true),
    SymptomDef(code: 'shortness_breath', label: 'Shortness of breath', icon: 'air'),
    SymptomDef(code: 'blurred_vision', label: 'Blurred vision', icon: 'visibility_off'),
    SymptomDef(code: 'numbness', label: 'Numbness/tingling', icon: 'touch_app'),
    SymptomDef(code: 'excessive_thirst', label: 'Excessive thirst', icon: 'local_drink'),
    SymptomDef(code: 'frequent_urination', label: 'Frequent urination', icon: 'wc'),
  ];

  // ── TB Symptoms ──────────────────────────────────────────────────────────
  static const tbSymptoms = [
    SymptomDef(code: 'cough_2weeks', label: 'Cough > 2 weeks', icon: 'air', isDangerSign: true),
    SymptomDef(code: 'night_sweats', label: 'Night sweats', icon: 'nightlight'),
    SymptomDef(code: 'weight_loss', label: 'Weight loss', icon: 'trending_down'),
    SymptomDef(code: 'fever', label: 'Fever', icon: 'thermostat'),
    SymptomDef(code: 'chest_pain', label: 'Chest pain', icon: 'favorite'),
    SymptomDef(code: 'blood_sputum', label: 'Blood in sputum', icon: 'water_drop', isDangerSign: true),
    SymptomDef(code: 'fatigue', label: 'Fatigue', icon: 'battery_alert'),
    SymptomDef(code: 'loss_appetite', label: 'Loss of appetite', icon: 'no_food'),
  ];

  /// Get symptoms for a specific programme.
  static List<SymptomDef> forProgramme(Programme programme) {
    switch (programme) {
      case Programme.imci:
        return imciSymptoms;
      case Programme.anc:
        return ancSymptoms;
      case Programme.ncd:
        return ncdSymptoms;
      case Programme.tb:
        return tbSymptoms;
      case Programme.pnc:
        return ancSymptoms; // Use ANC symptoms for PNC
      case Programme.epi:
      case Programme.nutrition:
      case Programme.familyPlanning:
      case Programme.cataract:
      case Programme.eyeCare:
      case Programme.unknown:
        return []; // Generic/empty
    }
  }
}

/// A vital sign definition for the vitals capture step.
class VitalDef {
  const VitalDef({
    required this.code,
    required this.label,
    this.unit,
    this.icon,
    this.min,
    this.max,
    this.programmes = const {},
    this.isBooleanType = false,
    this.instruction,
    this.minAge,
    this.maxAge,
  });

  final String code;
  final String label;
  final String? unit;
  final String? icon;
  final double? min;
  final double? max;
  final Set<Programme> programmes;
  final bool isBooleanType;
  final String? instruction;
  final int? minAge; // Minimum age for this vital
  final int? maxAge; // Maximum age for this vital
}

/// Catalog of vital signs by programme.
class VitalCatalog {
  VitalCatalog._();

  // ── Common Vitals ────────────────────────────────────────────────────────
  static const commonVitals = [
    VitalDef(
      code: 'temperature',
      label: 'Temperature',
      unit: '°C',
      icon: 'thermostat',
      min: 35.0,
      max: 42.0,
      instruction: 'Use thermometer under armpit for 3 minutes',
    ),
    VitalDef(
      code: 'weight',
      label: 'Weight',
      unit: 'kg',
      icon: 'monitor_weight',
      min: 0.5,
      max: 200.0,
      instruction: 'Remove heavy clothing and shoes',
    ),
  ];

  // ── IMCI-specific Vitals ─────────────────────────────────────────────────
  static const imciVitals = [
    VitalDef(
      code: 'respiratory_rate',
      label: 'Respiratory rate',
      unit: '/min',
      icon: 'air',
      min: 10,
      max: 80,
      instruction: 'Count breaths for 1 full minute while child is calm',
      programmes: {Programme.imci},
    ),
    VitalDef(
      code: 'spo2',
      label: 'SpO2',
      unit: '%',
      icon: 'favorite',
      min: 70,
      max: 100,
      instruction: 'Use pulse oximeter on finger or toe',
      programmes: {Programme.imci},
    ),
    VitalDef(
      code: 'muac',
      label: 'MUAC',
      unit: 'cm',
      icon: 'straighten',
      min: 5,
      max: 25,
      instruction: 'Measure at midpoint of left upper arm',
      programmes: {Programme.imci},
    ),
    VitalDef(
      code: 'chest_indrawing',
      label: 'Chest in-drawing',
      icon: 'warning',
      isBooleanType: true,
      instruction: 'Observe lower chest wall while child breathes',
      programmes: {Programme.imci},
    ),
  ];

  // ── ANC-specific Vitals ──────────────────────────────────────────────────
  static const ancVitals = [
    VitalDef(
      code: 'bp_systolic',
      label: 'Blood pressure (systolic)',
      unit: 'mmHg',
      icon: 'favorite',
      min: 60,
      max: 250,
      instruction: 'Rest 5 minutes before measuring',
      programmes: {Programme.anc},
    ),
    VitalDef(
      code: 'bp_diastolic',
      label: 'Blood pressure (diastolic)',
      unit: 'mmHg',
      icon: 'favorite',
      min: 40,
      max: 150,
      programmes: {Programme.anc},
    ),
    VitalDef(
      code: 'fundal_height',
      label: 'Fundal height',
      unit: 'cm',
      icon: 'straighten',
      min: 10,
      max: 50,
      instruction: 'Measure from pubic symphysis to top of uterus',
      programmes: {Programme.anc},
    ),
    VitalDef(
      code: 'fetal_heart_rate',
      label: 'Fetal heart rate',
      unit: 'bpm',
      icon: 'child_care',
      min: 100,
      max: 180,
      instruction: 'Use fetoscope or doppler',
      programmes: {Programme.anc},
    ),
    VitalDef(
      code: 'ankle_edema',
      label: 'Ankle edema',
      icon: 'bubble_chart',
      isBooleanType: true,
      instruction: 'Check both ankles for pitting edema',
      programmes: {Programme.anc},
    ),
  ];

  // ── NCD-specific Vitals ──────────────────────────────────────────────────
  static const ncdVitals = [
    VitalDef(
      code: 'bp_systolic',
      label: 'Blood pressure (systolic)',
      unit: 'mmHg',
      icon: 'favorite',
      min: 60,
      max: 250,
      instruction: 'Rest 5 minutes, sit upright, feet flat on floor',
      programmes: {Programme.ncd},
    ),
    VitalDef(
      code: 'bp_diastolic',
      label: 'Blood pressure (diastolic)',
      unit: 'mmHg',
      icon: 'favorite',
      min: 40,
      max: 150,
      programmes: {Programme.ncd},
    ),
    VitalDef(
      code: 'glucose',
      label: 'Blood glucose',
      unit: 'mg/dL',
      icon: 'bloodtype',
      min: 30,
      max: 600,
      instruction: 'Fasting or random - note which',
      programmes: {Programme.ncd},
    ),
    VitalDef(
      code: 'height',
      label: 'Height',
      unit: 'cm',
      icon: 'height',
      min: 50,
      max: 250,
      instruction: 'Stand straight against wall, no shoes',
      programmes: {Programme.ncd},
    ),
  ];

  // ── TB-specific Vitals ───────────────────────────────────────────────────
  static const tbVitals = [
    VitalDef(
      code: 'respiratory_rate',
      label: 'Respiratory rate',
      unit: '/min',
      icon: 'air',
      min: 10,
      max: 40,
      instruction: 'Count breaths for 1 full minute',
      programmes: {Programme.tb},
    ),
    VitalDef(
      code: 'spo2',
      label: 'SpO2',
      unit: '%',
      icon: 'favorite',
      min: 70,
      max: 100,
      instruction: 'Use pulse oximeter on finger',
      programmes: {Programme.tb},
    ),
  ];

  /// Get vitals for a specific programme.
  static List<VitalDef> forProgramme(Programme programme, int? patientAge) {
    final vitals = <VitalDef>[...commonVitals];

    switch (programme) {
      case Programme.imci:
        vitals.addAll(imciVitals);
        break;
      case Programme.anc:
      case Programme.pnc:
        vitals.addAll(ancVitals);
        break;
      case Programme.ncd:
        vitals.addAll(ncdVitals);
        break;
      case Programme.tb:
        vitals.addAll(tbVitals);
        break;
      case Programme.epi:
      case Programme.nutrition:
      case Programme.familyPlanning:
        break;
      case Programme.cataract:
      case Programme.eyeCare:
        vitals.addAll(ncdVitals);
        break;
      case Programme.unknown:
        // Include basic BP for unknown/general
        vitals.add(ncdVitals[0]); // Systolic
        vitals.add(ncdVitals[1]); // Diastolic
        break;
    }

    // Filter by age if specified
    if (patientAge != null) {
      return vitals.where((v) {
        if (v.minAge != null && patientAge < v.minAge!) return false;
        if (v.maxAge != null && patientAge > v.maxAge!) return false;
        return true;
      }).toList();
    }

    return vitals;
  }
}
