/// Input models for the CDSS algorithm engine.
///
/// Pure Dart — no Flutter dependencies. All values are passed in by the
/// caller (CdssEngine or a unit test); no I/O is performed here.
library;

// ── BP Reading ─────────────────────────────────────────────────────────────────

/// One systolic BP reading from a prior visit.
///
/// [visitIndex] is 0 for the oldest reading, increasing toward the most recent.
/// Used by the trend algorithms (CUSUM, EWMA, Linear Slope).
class BpReading {
  const BpReading({required this.systolic, required this.visitIndex});

  final int systolic;
  final int visitIndex;
}

// ── Patient Profile ────────────────────────────────────────────────────────────

/// Demographic and clinical facts needed by FINDRISC and Framingham.
///
/// BMI is passed as a pre-computed value (height/weight already collected in
/// the NCD form). Waist circumference is optional — FINDRISC computes a partial
/// score when it is absent.
class CdssPatientProfile {
  const CdssPatientProfile({
    required this.ageYears,
    required this.isFemale,
    this.bmi,
    this.systolicBp,
    this.waistCm,
    this.onBpMedication = false,
    this.isSmoker = false,
    this.hasDiabetes = false,
    this.isPhysicallyActive = false,
    this.eatsDailyFruitVeg = false,
    this.hadPreviousHighGlucose = false,
    this.hasFamilyHistoryDm = false,
  });

  /// Age in whole years.
  final int ageYears;

  /// true = female, false = male. Affects waist thresholds (FINDRISC) and
  /// the sex-stratified logistic formula (Framingham).
  final bool isFemale;

  /// Body-mass index kg/m². Null → Framingham skipped.
  final double? bmi;

  /// Most-recent systolic BP reading (mmHg). Null → Framingham skipped.
  final int? systolicBp;

  /// Waist circumference in cm. Null → waist points omitted from FINDRISC.
  final double? waistCm;

  /// Currently on antihypertensive medication. Affects Framingham β_SBP.
  final bool onBpMedication;

  /// Current or past regular smoker (≥ 12 months). Framingham input.
  final bool isSmoker;

  /// Known diabetes (type 1 or 2). Framingham input.
  final bool hasDiabetes;

  /// Physically active ≥ 30 min/day. FINDRISC input.
  final bool isPhysicallyActive;

  /// Eats vegetables and/or fruit daily. FINDRISC input.
  final bool eatsDailyFruitVeg;

  /// Previous blood glucose measured as high (non-fasting / gestational).
  /// FINDRISC input.
  final bool hadPreviousHighGlucose;

  /// First-degree relative with diabetes. FINDRISC input.
  final bool hasFamilyHistoryDm;
}

// ── Maternal Profile ────────────────────────────────────────────────────────────

/// Inputs required by the miniPIERS pre-eclampsia risk model.
///
/// All fields are optional — the calculator returns [MiniPiersResult.insufficientData]
/// when [gestationalWeeks] or [systolicBp] is null.
class MaternalProfile {
  const MaternalProfile({
    this.gestationalWeeks,
    this.systolicBp,
    this.proteinuriaGrade = 0,
    this.hasHeadache = false,
    this.hasChestPain = false,
  });

  /// Gestational age in completed weeks. Null → result marked insufficient.
  final int? gestationalWeeks;

  /// Systolic blood pressure (mmHg). Null → result marked insufficient.
  final int? systolicBp;

  /// Dipstick proteinuria grade:
  ///   0 = none, 1 = trace, 2 = +1, 3 = ≥ +2 (maps to urinaryAlbumin field).
  final int proteinuriaGrade;

  /// Headache present at this visit.
  final bool hasHeadache;

  /// Chest pain present at this visit.
  final bool hasChestPain;
}
