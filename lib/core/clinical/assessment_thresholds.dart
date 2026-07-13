library;

// ── BP (form input bounds — Screening) ──
const double bpFormMin = 50.0; // mmHg floor
const double bpFormMax = 300.0; // mmHg ceiling
const double pulseFormMin = 50.0; // bpm floor
const double pulseFormMax = 300.0; // bpm ceiling

// ── BP (clinical thresholds — AssessmentDefinedParams + NCDReferralColorEvaluator) ──
const double bpHighSystolic = 140.0;
const double bpHighDiastolic = 90.0;
const double bpCrisisSystolic = 180.0;
const double bpCrisisDiastolic = 110.0;
const double bpHypotensionSystolic = 90.0;
const double bpHypotensionDiastolic = 60.0;
const double bpYellowLowSystolicMax = 159.0;
const double bpYellowLowDiastolicMax = 99.0;
const double upazilaUpperLimitSystolic = 160.0;
const double upazilaUpperLimitDiastolic = 100.0;

// ── Temperature (°F — AssessmentDefinedParams) ──
const double tempHighFeverF = 102.0;
const double tempMildFeverMinF = 100.0;
const double tempMildFeverMaxF = 101.9;

// ── Pulse (bpm — AssessmentDefinedParams) ──
const double pulseHigh = 90.0;
const double pulseLow = 60.0;

// ── Haemoglobin (g/dL — AssessmentDefinedParams) ──
const double hbSevereAnaemia = 8.0;
const double hbModerateAnaemia = 10.0;
const double hbMildAnaemia = 11.0;
const double hbNormal = 11.0;

// ── Blood glucose (mmol/L — NCDReferralColorEvaluator + AssessmentDefinedParams) ──
const double bgHypoglycaemiaMmol = 3.9;
const double bgRedMmol = 27.8;
const double bgOrangeLowMmol = 16.7;
const double bgYellowHighMmol = 13.9;
const double fbsYellowLowMmol = 7.0;
const double rbsGreenHighMmol = 9.9;
const double mgdlToMmol = 18.0182;

// ── ANC blood glucose screening thresholds (mmol/L) ──
const double ancFbsDiabetesMmol = 5.1;
const double ancRbsDiabetesMmol = 8.5;

// ── PNC blood glucose thresholds (mmol/L) ──
const double pncFbsHighMmol = 7.0;
const double pncRbsHighMmol = 11.1;

// ── NCD controlled/uncontrolled gate (mmol/L) ──
const double ncdControlledFbsMax = 7.0;
const double ncdControlledRbsMax = 11.0;
const double ncdUncontrolledFbs = 7.1;
const double ncdUncontrolledRbs = 11.1;

// ── NCD screening glucose bounds ──
const double fbsScreeningNormal = 6.1;
const double fbsScreeningMax = 15.0;
const double rbsScreeningNormal = 7.8;
const double rbsScreeningMax = 15.0;

// ── BMI (kg/m²) ──
const double bmiUnderweight = 18.5;
const double bmiOverweight = 25.0;
const double bmiObese = 30.0;

// ── NCD controlled/uncontrolled gate (BP) ──
const double ncdUncontrolledSystolic = 141.0;  // systolic >= 141 → uncontrolled
const double ncdUncontrolledDiastolic = 91.0;  // diastolic >= 91 → uncontrolled

// ── High-risk pregnancy ──
const int pregnancyAgeMin = 18;
const int pregnancyAgeMax = 35;
const double birthSpacingThresholdYears = 2.0;
const int parityHighRisk = 3;
const double fundalHeightToleranceCm = 2.0;
const double heightLowCm = 145.0;
const double weightLowKg = 45.0;

// ── CVD risk bands (%) ──
const double cvdVeryLowRisk = 5.0;
const double cvdLowRisk = 10.0;
const double cvdMediumRisk = 20.0;
const double cvdMediumHighRisk = 30.0;
