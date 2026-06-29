import 'programme.dart';

/// Structured rationale payload for AI explainability (architecture.md §3.4).
///
/// Every AI output carries this shape so the SK can understand *why* a patient
/// scored high. The `drivers` list contains machine-readable tags (e.g.
/// 'anc-danger-sign', 'ncd-htn-stage2:160/100') which the UI localises into
/// human-readable `reasons` via [formattedReasons].
class RiskRationale {
  const RiskRationale({
    required this.drivers,
    required this.modelVersion,
    required this.computedAt,
    this.confidence,
    this.humanReviewRequired = false,
    this.guidelineIds = const <String>[],
    this.sourceObservationIds = const <String>[],
  });

  final List<String> drivers;
  final String modelVersion;
  final DateTime computedAt;
  final double? confidence;
  final bool humanReviewRequired;
  final List<String> guidelineIds;
  final List<String> sourceObservationIds;

  List<String> get formattedReasons {
    return drivers.map(_formatDriver).toList(growable: false);
  }

  static String _formatDriver(String driver) {
    final parts = driver.split(':');
    final key = parts[0];
    final value = parts.length > 1 ? parts[1] : null;

    switch (key) {
      case 'under-5':
        return value != null ? 'Under-5 child (age $value)' : 'Under-5 child';
      case 'senior':
        return value != null ? 'Senior (age $value)' : 'Senior';
      case 'pregnancy':
        return 'Pregnancy / ANC enrolled';
      case 'ncd':
        return 'NCD enrolment';
      case 'tb':
        return 'TB enrolment';
      case 'imci':
        return 'IMCI eligibility';
      case 'missed-visits':
        return '$value missed visit(s) in last 90 days';
      case 'lost-to-follow-up':
        return 'Lost to follow-up';
      case 'server-risk-red':
        return 'Server risk flag: red';
      case 'server-risk-yellow':
        return 'Server risk flag: yellow';
      case 'server-risk-high':
        return 'Server risk level: HIGH';
      case 'clinician-red-flag':
        return 'Patient flagged red by clinician';
      case 'no-programme':
        return 'No programme enrolment recorded';
      case 'anc-danger-sign':
        return 'ANC: danger sign present — immediate referral';
      case 'anc-eclampsia':
        return 'ANC: eclampsia / pre-eclampsia pattern';
      case 'anc-bp-severe':
        return value != null ? 'ANC: severe hypertension ($value)' : 'ANC: severe hypertension';
      case 'anc-bp-elevated':
        return value != null ? 'ANC: elevated BP ($value)' : 'ANC: elevated BP';
      case 'anc-anaemia-severe':
        return value != null ? 'ANC: severe anaemia (Hb $value g/dL)' : 'ANC: severe anaemia';
      case 'anc-anaemia-moderate':
        return value != null ? 'ANC: moderate anaemia (Hb $value g/dL)' : 'ANC: moderate anaemia';
      case 'anc-anaemia-mild':
        return value != null ? 'ANC: mild anaemia (Hb $value g/dL)' : 'ANC: mild anaemia';
      case 'anc-urine-abnormal':
        return value != null ? 'ANC: abnormal urine ($value)' : 'ANC: abnormal urine';
      case 'anc-gdm-risk':
        return value != null ? 'ANC: GDM risk (fasting $value mmol/L)' : 'ANC: GDM risk';
      case 'anc-late-term':
        return value != null ? 'ANC: ≥ 36 weeks ($value wks)' : 'ANC: ≥ 36 weeks';
      case 'anc-primigravida':
        return 'ANC: first pregnancy (primigravida)';
      case 'anc-missed-visit':
        return value != null ? 'ANC: missed visit ($value overdue)' : 'ANC: missed visit';
      case 'ncd-stroke-sign':
        return 'NCD: one-sided weakness — stroke warning';
      case 'ncd-htn-crisis':
        return value != null ? 'NCD: hypertensive crisis (BP $value)' : 'NCD: hypertensive crisis';
      case 'ncd-htn-stage2':
        return value != null ? 'NCD: stage 2 hypertension (BP $value)' : 'NCD: stage 2 hypertension';
      case 'ncd-htn-stage1':
        return value != null ? 'NCD: stage 1 hypertension (BP $value)' : 'NCD: stage 1 hypertension';
      case 'ncd-prehtn':
        return value != null ? 'NCD: pre-hypertension ($value)' : 'NCD: pre-hypertension';
      case 'ncd-dm-crisis':
        return value != null ? 'NCD: diabetic crisis (fasting $value mmol/L)' : 'NCD: diabetic crisis';
      case 'ncd-dm-poor-control':
        return value != null ? 'NCD: poorly controlled diabetes (fasting $value mmol/L)' : 'NCD: poorly controlled diabetes';
      case 'ncd-dm-elevated':
        return value != null ? 'NCD: elevated glucose (fasting $value mmol/L)' : 'NCD: elevated glucose';
      case 'ncd-prediabetes':
        return value != null ? 'NCD: pre-diabetes (fasting $value mmol/L)' : 'NCD: pre-diabetes';
      case 'ncd-comorbid-htn-dm':
        return 'NCD: hypertension + diabetes (compounded risk)';
      case 'ncd-elderly':
        return value != null ? 'NCD: elderly patient (age $value)' : 'NCD: elderly patient';
      case 'ncd-missed-followup':
        return value != null ? 'NCD: missed follow-up ($value overdue)' : 'NCD: missed follow-up';
      default:
        return driver;
    }
  }

  Map<String, dynamic> toJson() => {
        'drivers': drivers,
        'modelVersion': modelVersion,
        'computedAt': computedAt.toIso8601String(),
        if (confidence != null) 'confidence': confidence,
        'humanReviewRequired': humanReviewRequired,
        'guidelineIds': guidelineIds,
        'sourceObservationIds': sourceObservationIds,
      };

  factory RiskRationale.fromJson(Map<String, dynamic> json) => RiskRationale(
        drivers: (json['drivers'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        modelVersion: json['modelVersion'] as String? ?? 'unknown',
        computedAt: json['computedAt'] != null
            ? DateTime.parse(json['computedAt'] as String)
            : DateTime.now(),
        confidence: (json['confidence'] as num?)?.toDouble(),
        humanReviewRequired: json['humanReviewRequired'] as bool? ?? false,
        guidelineIds: (json['guidelineIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
        sourceObservationIds: (json['sourceObservationIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const <String>[],
      );
}

/// Severity band — spec §2.8.3.
///
/// The worst single clinical finding sets the band. No composite score.
/// Band 1 is the most severe. Bands are an enum (not free strings) so list
/// ordering, color mapping, and chip filtering can be exhaustive — `switch`
/// on this enum becomes a compile-time gate when a new band is added.
enum Band {
  band1, // Severe   — Red, NOW
  band2, // Moderate — Amber, TODAY
  band3, // Mild     — Navy, TODAY / THIS WEEK
  band4; // Routine  — Grey, ROUTINE

  String get wireTag {
    switch (this) {
      case Band.band1:
        return 'band1';
      case Band.band2:
        return 'band2';
      case Band.band3:
        return 'band3';
      case Band.band4:
        return 'band4';
    }
  }

  static Band fromWireTag(String? tag) {
    switch ((tag ?? '').toLowerCase()) {
      case 'band1':
        return Band.band1;
      case 'band2':
        return Band.band2;
      case 'band3':
        return Band.band3;
      default:
        return Band.band4;
    }
  }
}

/// Within-band modifier — spec §2.8.1 / §2.8.2.
///
/// `a` = additional risk (comorbidity, first pregnancy, GA ≥ 36 weeks, age ≥ 60).
/// `b` = overdue (longer past scheduled visit ranks higher within b, but below a).
/// `none` = no modifier — base position within band.
///
/// Spec sort: 1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4.
enum Modifier {
  a,
  b,
  none;

  String get wireTag {
    switch (this) {
      case Modifier.a:
        return 'a';
      case Modifier.b:
        return 'b';
      case Modifier.none:
        return 'none';
    }
  }

  static Modifier fromWireTag(String? tag) {
    switch ((tag ?? '').toLowerCase()) {
      case 'a':
        return Modifier.a;
      case 'b':
        return Modifier.b;
      default:
        return Modifier.none;
    }
  }
}

/// Numeric sort key for SQL `ORDER BY ... DESC`.
///
/// Higher value = higher priority on the worklist.
///
/// Scheme (10-point gaps so future tie-break bumps fit cleanly):
///   Band base: band1=1000, band2=700, band3=400, band4=100
///   Modifier offset within band: a=+30, b=+20, none=+10
///
/// Spec §2.8 sort emerges naturally: 1a (1030) → 1b (1020) → 1 (1010)
///   → 2a (730) → 2b (720) → 2 (710) → 3a (430) → 3b (420) → 3 (410) → 4 (110).
///
/// Pregnancy is *not* baked into the sort key — it is a secondary sort
/// applied in the repository, since pregnancy boost must apply within band
/// regardless of modifier.
int sortRankFor(Band band, Modifier modifier) {
  final base = switch (band) {
    Band.band1 => 1000,
    Band.band2 => 700,
    Band.band3 => 400,
    Band.band4 => 100,
  };
  final mod = switch (modifier) {
    Modifier.a => 30,
    Modifier.b => 20,
    Modifier.none => 10,
  };
  return base + mod;
}

/// Extracted clinical vitals from the most recent local assessment.
/// All fields nullable — missing data is treated as "not present", which
/// is conservative for the worst-finding rule (we never *infer* severity).
class ClinicalVitals {
  const ClinicalVitals({
    this.systolicBp,
    this.diastolicBp,
    this.hemoglobin,
    this.fastingGlucoseMmolL,
    this.hasDangerSign = false,
    this.hasEclampsia = false,
    this.hasStrokeSign = false,
    this.hasAbnormalUrine = false,
    this.gestationalAgeWeeks,
    this.parity,
    this.hasDiabetes = false,
    this.assessmentType,
  });

  final int? systolicBp;
  final int? diastolicBp;
  final double? hemoglobin;             // g/dL
  final double? fastingGlucoseMmolL;    // mmol/L (spec §2.8 uses mmol/L)
  final bool hasDangerSign;             // any ANC danger sign present
  final bool hasEclampsia;              // ANC pre-eclampsia pattern (3-visit trend)
  final bool hasStrokeSign;             // NCD one-sided weakness / stroke warning
  final bool hasAbnormalUrine;          // ANC abnormal urine (protein/glucose/infection)
  final int? gestationalAgeWeeks;       // ANC GA in weeks
  final int? parity;                    // 0 = primigravida
  final bool hasDiabetes;               // patient is on DM register
  final String? assessmentType;         // 'NCD' or 'ANC'
}

/// Inputs to [RiskScoringService.score]. Built by the worklist repository as a
/// single join over the cached SQLite rows — never assembled from a network
/// call directly (offline-first tenet).
class PatientFacts {
  const PatientFacts({
    required this.patientId,
    this.ageYears,
    this.programmes = const <Programme>{},
    this.missedVisitsLast90d = 0,
    this.daysSinceLastVisit,
    this.nextDueAt,
    this.lostToFollowUp = false,
    this.redFlag = false,
    this.serverRiskLevel,
    this.serverRiskColor,
    this.diagnosisCount = 0,
    this.vitals,
  });

  final String patientId;
  final int? ageYears;
  final Set<Programme> programmes;
  final int missedVisitsLast90d;
  final int? daysSinceLastVisit;
  final DateTime? nextDueAt;
  final bool lostToFollowUp;
  final bool redFlag;
  final String? serverRiskLevel;
  final String? serverRiskColor;
  final int diagnosisCount;
  final ClinicalVitals? vitals;

  bool get isPregnant => programmes.contains(Programme.anc);
}

/// The risk-engine output. Persisted into the `patients` row so the worklist
/// query is a simple `ORDER BY risk_score DESC` — where `risk_score` is now
/// the [sortRank] of the (band, modifier) pair.
class RiskAssessment {
  const RiskAssessment({
    required this.band,
    required this.modifier,
    required this.programmes,
    required this.reasons,
    this.rationale,
  });

  final Band band;
  final Modifier modifier;
  final Set<Programme> programmes;

  /// Short human-readable rationale lines (Tenet 6: Explainable).
  /// Derived from [rationale.drivers] when structured rationale is available.
  final List<String> reasons;

  /// Structured rationale payload (architecture.md §3.4 contract).
  final RiskRationale? rationale;

  /// Sort key persisted into `patients.risk_score` so SQL ORDER BY DESC
  /// produces the spec sequence (1a → 1b → 1 → 2a → 2b → 2 → 3a → 3b → 3 → 4).
  int get sortRank => sortRankFor(band, modifier);

  bool get isUrgent => band == Band.band1;
}
