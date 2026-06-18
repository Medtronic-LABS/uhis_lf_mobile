/// Output models for the CDSS algorithm engine.
///
/// Pure Dart — no Flutter dependencies. Each calculator returns its own result
/// type. [CdssEngineOutput] aggregates all six.
library;

// ── FINDRISC ──────────────────────────────────────────────────────────────────

class FindriscResult {
  const FindriscResult({
    required this.score,
    required this.riskLevel,
    required this.riskPct,
    required this.trigger,
    this.waistOmitted = false,
  });

  /// Raw FINDRISC score (0–26; partial when waist omitted).
  final int score;

  /// WHO/FINDRISC risk band: 'low' | 'slightly_elevated' | 'moderate' |
  /// 'high' | 'very_high'.
  final String riskLevel;

  /// Approximate 10-year type-2 DM probability (%).
  final double riskPct;

  /// true when score ≥ 12 — NCD programme triggered.
  final bool trigger;

  /// true when waist circumference was absent; score excludes waist points.
  final bool waistOmitted;
}

// ── Framingham ────────────────────────────────────────────────────────────────

class FraminghamResult {
  const FraminghamResult({
    required this.riskPct,
    required this.trigger,
    required this.highRisk,
    this.insufficientData = false,
  });

  /// 10-year CVD risk percentage (0–100).
  final double riskPct;

  /// true when riskPct ≥ 10 — NCD programme triggered.
  final bool trigger;

  /// true when riskPct ≥ 20 — immediate clinical review required.
  final bool highRisk;

  /// true when required inputs were absent (age < 18, bmi null, sbp null).
  final bool insufficientData;
}

// ── CUSUM ─────────────────────────────────────────────────────────────────────

class CusumResult {
  const CusumResult({
    required this.insufficientData,
    required this.alert,
    required this.finalS,
  });

  /// true when fewer than 2 prior readings are available.
  final bool insufficientData;

  /// true when the cumulative sum S exceeds the decision interval h = 40.
  final bool alert;

  /// Final value of the running sum S.
  final double finalS;
}

// ── EWMA ─────────────────────────────────────────────────────────────────────

class EwmaResult {
  const EwmaResult({
    required this.insufficientData,
    required this.alert,
    required this.ewmaValue,
    required this.ucl,
  });

  /// true when fewer than 2 prior readings are available.
  final bool insufficientData;

  /// true when the smoothed EWMA value exceeds the UCL.
  final bool alert;

  /// Final smoothed EWMA value.
  final double ewmaValue;

  /// Upper control limit = μ₀ + 3σ√(λ/(2−λ)) ≈ μ₀ + 14.1.
  final double ucl;
}

// ── Linear Slope ──────────────────────────────────────────────────────────────

class SlopeResult {
  const SlopeResult({
    required this.insufficientData,
    required this.alert,
    required this.slopeMmHgPerVisit,
  });

  /// true when fewer than 2 prior readings are available.
  final bool insufficientData;

  /// true when OLS slope exceeds 4 mmHg/visit.
  final bool alert;

  /// OLS regression slope in mmHg per visit.
  final double slopeMmHgPerVisit;
}

// ── miniPIERS ─────────────────────────────────────────────────────────────────

class MiniPiersResult {
  const MiniPiersResult({
    required this.insufficientData,
    required this.riskPct,
    required this.trigger,
    required this.critical,
  });

  /// true when gestational weeks or systolic BP is absent.
  final bool insufficientData;

  /// Pre-eclampsia probability (0–100 %).
  final double riskPct;

  /// true when riskPct ≥ 25 — RMNCH programme triggered + teleconsult.
  final bool trigger;

  /// true when riskPct ≥ 50 — immediate facility referral.
  final bool critical;
}

// ── Engine Output ─────────────────────────────────────────────────────────────

/// Aggregated output of [CdssEngine.evaluate].
///
/// Null fields mean the corresponding algorithm was not run (inputs absent).
class CdssEngineOutput {
  const CdssEngineOutput({
    this.findrisc,
    this.framingham,
    this.cusum,
    this.ewma,
    this.slope,
    this.miniPiers,
  });

  final FindriscResult? findrisc;
  final FraminghamResult? framingham;
  final CusumResult? cusum;
  final EwmaResult? ewma;
  final SlopeResult? slope;
  final MiniPiersResult? miniPiers;

  /// Any of the three BP-trend algorithms fired an alert.
  bool get anyTrendAlert =>
      (cusum?.alert ?? false) ||
      (ewma?.alert ?? false) ||
      (slope?.alert ?? false);

  /// NCD programme should be triggered based on algorithmic outputs.
  bool get ncdTriggered =>
      (findrisc?.trigger ?? false) ||
      (framingham?.trigger ?? false) ||
      anyTrendAlert;

  /// ANC/RMNCH escalation from miniPIERS.
  bool get ancTriggerMiniPiers => miniPiers?.trigger ?? false;
}
