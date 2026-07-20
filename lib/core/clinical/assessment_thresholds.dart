library;

// ── BP (form input bounds — Screening) ──
// `0` is accepted separately as the documented "could not be measured"
// sentinel (field_library.json `infoTitle` on `systolic`/`diastolic`).
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

// ── Temperature (°C — derived from °F constants via formal conversion) ──
// Conversion: °C = (°F − 32) × 5/9
const double tempHighFeverC = 38.89;       // 102°F
const double tempMildFeverMinC = 37.78;    // 100°F
const double tempMildFeverMaxC = 38.83;    // 101.9°F
const double tempHypothermiaC = 35.0;
const double tempNormalMinC = 36.1;
const double tempNormalMaxC = 37.5;

/// Form input bounds for temperature entry — the `temperature` field is
/// captured in °F (field_library.json `unitMeasurement: "°F"`), so these are
/// deliberately wide Fahrenheit bounds, not the clinical fever thresholds
/// above. `0` is accepted separately as the documented "could not be
/// measured" sentinel (field_library.json `infoTitle`).
const double tempFormMinF = 90.0;
const double tempFormMaxF = 110.0;

// ── Form input plausibility checks — pure predicates so Step 2's numeric
//    range validators are unit-testable independent of the Form/widget layer.
bool isPlausibleTemperatureF(double f) =>
    f == 0 || (f >= tempFormMinF && f <= tempFormMaxF);
bool isPlausibleBpReading(double v) => v == 0 || (v >= bpFormMin && v <= bpFormMax);
bool isPlausibleFundalHeightCm(double cm) =>
    cm >= fundalHeightFormMinCm && cm <= fundalHeightFormMaxCm;

// ── Temperature conversion utilities ──
double fahrenheitToCelsius(double f) => (f - 32) * 5 / 9;
double celsiusToFahrenheit(double c) => c * 9 / 5 + 32;

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

// ── HbA1c (% — referral and form bounds) ──
// ≥ 6.5% = diabetes diagnosis threshold
// ≥ 8.0% = uncontrolled DM → yellowHigh referral
// ≥ 10.0% = very poorly controlled → orange referral
// Form bounds: 4.0–14.0% (clinically plausible range)
const double hba1cFormMin = 4.0;
const double hba1cFormMax = 14.0;
const double hba1cDiabetesThreshold = 6.5;
const double hba1cUncontrolled = 8.0;
const double hba1cCrisis = 10.0;

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

/// Form input bounds for fundal-height entry (cm) — deliberately wide to
/// avoid rejecting a genuine outlier reading (e.g. twin pregnancy).
const double fundalHeightFormMinCm = 8.0;
const double fundalHeightFormMaxCm = 45.0;

// ── CVD risk bands (%) ──
const double cvdVeryLowRisk = 5.0;
const double cvdLowRisk = 10.0;
const double cvdMediumRisk = 20.0;
const double cvdMediumHighRisk = 30.0;

// ── ANC gap thresholds (matches Android AssessmentDefinedParams) ──
// TT/TD gap: incomplete vaccination after 20 gestational weeks.
const double ancGestationalAgeWeek20 = 20.0;
// USG / doctor-visit / ANC-count gap: evaluated at 36 weeks.
const double ancGestationalAgeWeek36 = 36.0;
// Minimum ANC visits required by 36 weeks before flagging as a gap.
const int ancMinVisitsRequired = 3;
// Minimum tablet doses consumed (IFA / Calcium) to not flag as inadequate.
const int ancTabletConsumptionMin = 30;
