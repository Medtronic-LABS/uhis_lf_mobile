/// Clinical referral evaluators — ANC, PNC, and NCD pathways.
///
/// All thresholds sourced from assessment_thresholds.dart (single source of
/// truth). These are pure functions — no Flutter dependencies.
library;

import 'assessment_thresholds.dart';
import '../../features/visit/models/anc_assessment.dart';

// ─── Result types ─────────────────────────────────────────────────────────────

/// NCD 4-band risk classification (matches Android NCDReferralColorEvaluator).
enum NcdRiskBand { green, yellowLow, yellowHigh, orange, red }

class NcdReferralResult {
  const NcdReferralResult({
    required this.band,
    this.referralReasons = const [],
  });

  final NcdRiskBand band;

  /// Which dimensions triggered the result: 'bloodPressure', 'bloodGlucose', 'symptoms'.
  final List<String> referralReasons;

  bool get isReferralRequired => band != NcdRiskBand.green;

  /// Hex color for UI risk banner — matches Android color assignments.
  String get hexColor => switch (band) {
        NcdRiskBand.red => '#FF0000',
        NcdRiskBand.orange => '#FF8C00',
        NcdRiskBand.yellowHigh => '#FFC000',
        NcdRiskBand.yellowLow => '#FFE066',
        NcdRiskBand.green => '#00B050',
      };
}

class AncReferralResult {
  const AncReferralResult({
    this.emergencyConditions = const [],
    this.nonEmergencyConditions = const [],
  });

  final List<String> emergencyConditions;
  final List<String> nonEmergencyConditions;

  bool get isEmergencyReferral => emergencyConditions.isNotEmpty;
  bool get isNonEmergencyReferral => nonEmergencyConditions.isNotEmpty;
  bool get isReferralRequired => isEmergencyReferral || isNonEmergencyReferral;
}

/// ANC care-gap summary (mirrors Android ANCAssessmentEvaluator.evaluateGapsInANC).
///
/// Carried in [AncSummary.gapsInAnc] and sent in the offline-sync payload
/// so the server can display gap flags without re-evaluating client logic.
class AncGapsResult {
  const AncGapsResult({this.gaps = const []});

  final List<String> gaps;
  bool get hasGaps => gaps.isNotEmpty;
}

class PncReferralResult {
  const PncReferralResult({
    this.urgentConditions = const [],
    this.nonUrgentConditions = const [],
  });

  final List<String> urgentConditions;
  final List<String> nonUrgentConditions;

  bool get isUrgentReferral => urgentConditions.isNotEmpty;
  bool get isNonUrgentReferral => nonUrgentConditions.isNotEmpty;
  bool get isReferralRequired => isUrgentReferral || isNonUrgentReferral;
}

// ─── NCD Referral Evaluator ───────────────────────────────────────────────────

/// Produces a 4-band risk result from a single NCD visit's BP and glucose.
///
/// Evaluates hypertension and diabetes independently; the worse band wins.
/// Equivalent to Android's NCDReferralColorEvaluator.
class NcdReferralEvaluator {
  NcdReferralEvaluator._();

  static NcdReferralResult evaluate({
    double? systolic,
    double? diastolic,
    double? fastingGlucoseMmol,
    double? randomGlucoseMmol,
    List<String> symptoms = const [],
  }) {
    final bpBand = _bpBand(systolic, diastolic, symptoms);
    final bgBand = _bgBand(fastingGlucoseMmol, randomGlucoseMmol);
    final band = _worse(bpBand, bgBand);

    final reasons = <String>[];
    if (bpBand != NcdRiskBand.green) reasons.add('bloodPressure');
    if (bgBand != NcdRiskBand.green) reasons.add('bloodGlucose');
    if (symptoms.isNotEmpty && bpBand == NcdRiskBand.red) reasons.add('symptoms');

    return NcdReferralResult(band: band, referralReasons: reasons);
  }

  static NcdRiskBand _bpBand(
      double? sys, double? dia, List<String> symptoms) {
    if (sys == null || dia == null) return NcdRiskBand.green;
    final crisis = sys >= bpCrisisSystolic ||
        dia >= bpCrisisDiastolic ||
        sys < bpHypotensionSystolic ||
        dia < bpHypotensionDiastolic;
    if (crisis) {
      return symptoms.isNotEmpty ? NcdRiskBand.red : NcdRiskBand.orange;
    }
    if (sys >= 160 || dia >= 100) return NcdRiskBand.yellowHigh;
    if (sys >= bpHighSystolic || dia >= bpHighDiastolic) return NcdRiskBand.yellowLow;
    return NcdRiskBand.green;
  }

  static NcdRiskBand _bgBand(double? fbs, double? rbs) {
    final bg = rbs ?? fbs;
    if (bg == null) return NcdRiskBand.green;
    if (bg > bgRedMmol) return NcdRiskBand.red;
    if (bg < bgHypoglycaemiaMmol) return NcdRiskBand.orange;
    if (bg >= bgOrangeLowMmol) return NcdRiskBand.orange;
    if (bg >= bgYellowHighMmol) return NcdRiskBand.yellowHigh;
    if (fbs != null && fbs >= fbsYellowLowMmol) return NcdRiskBand.yellowLow;
    // Bangladesh spec: RBS ≥ 11.1 mmol/L → CC referral (yellowHigh), not just monitor.
    if (rbs != null && rbs >= ncdUncontrolledRbs) return NcdRiskBand.yellowHigh;
    if (rbs != null && rbs > rbsGreenHighMmol) return NcdRiskBand.yellowLow;
    return NcdRiskBand.green;
  }

  static NcdRiskBand _worse(NcdRiskBand a, NcdRiskBand b) {
    const order = [
      NcdRiskBand.green,
      NcdRiskBand.yellowLow,
      NcdRiskBand.yellowHigh,
      NcdRiskBand.orange,
      NcdRiskBand.red,
    ];
    return order.indexOf(a) >= order.indexOf(b) ? a : b;
  }
}

// ─── ANC Referral Evaluator ───────────────────────────────────────────────────

/// Full 14-condition ANC referral evaluation.
///
/// Takes an [AncAssessment] plus optional contextual parameters not stored in
/// the assessment model (age, parity, birth spacing, temperature, pulse).
/// Equivalent to Android's ANCAssessmentEvaluator.
class AncReferralEvaluator {
  AncReferralEvaluator._();

  static AncReferralResult evaluate(
    AncAssessment assessment, {
    int? patientAgeYears,
    int? parityCount,
    double? yearsFromLastBirth,
    double? temperatureCelsius,
    int? pulseBpm,
    bool? hasChronicIllness,
    bool? chronicIllnessOnTreatment,
  }) {
    final exam = assessment.medicalHistoryPhysicalExamination;
    final poci = assessment.pointOfCareInvestigations;

    final sys = exam?.bloodPressureSystolic?.toDouble();
    final dia = exam?.bloodPressureDiastolic?.toDouble();
    final hb = poci?.hemoglobin;
    final fbs = poci?.bloodSugarFasting;
    final rbs = poci?.bloodSugarRandom;
    final urineAlbumin = poci?.urinaryAlbumin;
    final urineBilirubin = poci?.urinaryBilirubin;
    final urineSugar = poci?.urinarySugar;
    final edema = exam?.oedema;
    final fh = exam?.fundalHeight;
    final ga = assessment.gestationalWeeks?.toDouble();
    final hasDangerSigns =
        assessment.dangerSignsRiskIdentification?.hasDangerSigns ?? false;
    final weight = exam?.weight;
    final height = exam?.height;

    final emergency = <String>[];
    final nonEmergency = <String>[];

    // ── Emergency conditions ──────────────────────────────────────────────────

    if (hasDangerSigns) emergency.add('Danger signs present');

    // Pre-eclampsia: BP ≥ 140/90 AND (albumin present OR edema present)
    final highBp = (sys != null && sys >= bpHighSystolic) ||
        (dia != null && dia >= bpHighDiastolic);
    final albuminPresent = _isPresent(urineAlbumin);
    final edemaPresent = _isPresent(edema);
    if (highBp && (albuminPresent || edemaPresent)) {
      emergency.add('Suspected pre-eclampsia');
    }

    // High fever ≥ 102°F — stored as °C; 102°F ≈ 38.9°C
    if (temperatureCelsius != null && temperatureCelsius >= 38.9) {
      emergency.add('High fever (≥102°F)');
    }

    // Fundal height deviation ± 2 cm from gestational weeks
    if (fh != null && ga != null && (fh - ga).abs() > fundalHeightToleranceCm) {
      emergency.add('Abnormal fundal height');
    }

    // Abnormal pulse: outside 60–90 bpm
    if (pulseBpm != null &&
        (pulseBpm > pulseHigh.toInt() || pulseBpm < pulseLow.toInt())) {
      emergency.add('Abnormal pulse');
    }

    // Severe anaemia: Hb < 8 g/dL
    if (hb != null && hb < hbSevereAnaemia) {
      emergency.add('Severe anaemia (Hb <8 g/dL)');
    }

    // Urinary bilirubin present
    if (_isPresent(urineBilirubin)) emergency.add('Urinary bilirubin present');

    // Chronic illness NOT on treatment
    if (hasChronicIllness == true && chronicIllnessOnTreatment == false) {
      emergency.add('Chronic illness untreated');
    }

    // ── Non-emergency conditions ──────────────────────────────────────────────

    // High-risk age: < 18 or > 35
    if (patientAgeYears != null &&
        (patientAgeYears < pregnancyAgeMin ||
            patientAgeYears > pregnancyAgeMax)) {
      nonEmergency.add('High-risk age (<18 or >35 years)');
    }

    // High parity: > 3 births
    if (parityCount != null && parityCount > parityHighRisk) {
      nonEmergency.add('High parity (>3 births)');
    }

    // Short birth spacing: < 2 years
    if (yearsFromLastBirth != null &&
        yearsFromLastBirth < birthSpacingThresholdYears) {
      nonEmergency.add('Birth spacing <2 years');
    }

    // Moderate anaemia: 8–10 g/dL
    if (hb != null && hb >= hbSevereAnaemia && hb < hbModerateAnaemia) {
      nonEmergency.add('Moderate anaemia (Hb 8–10 g/dL)');
    }

    // Mild anaemia: 10–11 g/dL
    if (hb != null && hb >= hbModerateAnaemia && hb < hbMildAnaemia) {
      nonEmergency.add('Mild anaemia (Hb 10–11 g/dL)');
    }

    // Suspected diabetes: urine sugar OR FBS ≥ 5.1 OR RBS ≥ 8.5 mmol/L
    final urineSugarPresent = _isPresent(urineSugar);
    final fbsDiabetes = fbs != null && fbs >= ancFbsDiabetesMmol;
    final rbsDiabetes = rbs != null && rbs >= ancRbsDiabetesMmol;
    if (urineSugarPresent || fbsDiabetes || rbsDiabetes) {
      nonEmergency.add('Suspected diabetes');
    }

    // Mild fever: 100–101.9°F — 37.8–38.8°C
    if (temperatureCelsius != null &&
        temperatureCelsius >= 37.8 &&
        temperatureCelsius < 38.9) {
      nonEmergency.add('Mild fever (100–101.9°F)');
    }

    // Low height or weight
    if (height != null && height < heightLowCm) {
      nonEmergency.add('Low height (<145 cm)');
    }
    if (weight != null && weight < weightLowKg) {
      nonEmergency.add('Low weight (<45 kg)');
    }

    // High BP without pre-eclampsia criteria (non-emergency)
    if (highBp && !emergency.contains('Suspected pre-eclampsia')) {
      nonEmergency.add('High blood pressure');
    }

    return AncReferralResult(
      emergencyConditions: emergency,
      nonEmergencyConditions: nonEmergency,
    );
  }

  /// Evaluates 8 ANC care-gap conditions from the form data.
  ///
  /// Mirrors Android `ANCAssessmentEvaluator.evaluateGapsInANC()`.
  /// Returns [AncGapsResult] whose [AncGapsResult.gaps] list is written into
  /// `summary.gapsInAnc` in the offline-sync payload.
  ///
  /// [ifaTotalConsumed] and [calciumTotalConsumed] are only checked when
  /// non-null — absence means the field wasn't filled in, not that zero were
  /// consumed, matching Android's `isViewVisible` guard.
  static AncGapsResult evaluateGaps({
    double? gestationalAgeWeeks,
    String? ttTdCompleted,
    String? ultrasound,
    String? ancFromMedicalDoctor,
    int? ifaTotalConsumed,
    int? calciumTotalConsumed,
    String? facilityIdentifiedForDelivery,
    int? ancVisitCount,
  }) {
    final gaps = <String>[];
    final ga = gestationalAgeWeeks ?? 0.0;

    // 1. TT/TD incomplete > 20 gestational weeks.
    if (ga > ancGestationalAgeWeek20) {
      final completed = ttTdCompleted?.toLowerCase();
      if (completed == null || completed.isEmpty || completed == 'no') {
        gaps.add('TT vaccination incomplete (>20 weeks)');
      }
    }

    // 2. Ultrasound not done > 36 weeks.
    if (ultrasound != null &&
        ultrasound.toLowerCase() == 'notdone' &&
        ga > ancGestationalAgeWeek36) {
      gaps.add('USG not done (>36 weeks)');
    }

    // 3. No ANC from medical doctor > 36 weeks.
    if (ancFromMedicalDoctor != null &&
        ancFromMedicalDoctor.toLowerCase() == 'no' &&
        ga > ancGestationalAgeWeek36) {
      gaps.add('ANC with doctor not done (>36 weeks)');
    }

    // 4. Fewer than 3 ANC visits completed by 36 weeks.
    if (ancVisitCount != null &&
        ancVisitCount < ancMinVisitsRequired &&
        ga >= ancGestationalAgeWeek36) {
      gaps.add('Less than 3 ANCs completed by 36 weeks');
    }

    // 5. Inadequate IFA tablet consumption (< 30).
    if (ifaTotalConsumed != null &&
        ifaTotalConsumed < ancTabletConsumptionMin) {
      gaps.add('Inadequate IFA consumption (<$ancTabletConsumptionMin tablets)');
    }

    // 6. Inadequate Calcium tablet consumption (< 30).
    if (calciumTotalConsumed != null &&
        calciumTotalConsumed < ancTabletConsumptionMin) {
      gaps.add('Inadequate Calcium consumption (<$ancTabletConsumptionMin tablets)');
    }

    // 7. Delivery facility not yet identified.
    if (facilityIdentifiedForDelivery?.toLowerCase() == 'notidentified') {
      gaps.add('Delivery facility not identified');
    }

    // 8. Planned home delivery.
    if (facilityIdentifiedForDelivery?.toLowerCase() == 'homedelivery') {
      gaps.add('Planned home delivery');
    }

    return AncGapsResult(gaps: gaps);
  }

  static bool _isPresent(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase();
    return v != 'absent' && v != 'negative' && v != 'none' && v != 'no';
  }
}

// ─── PNC Referral Evaluator ───────────────────────────────────────────────────

/// Full 9-condition urgent PNC referral evaluation.
///
/// Equivalent to Android's PNCAssessmentEvaluator.
class PncReferralEvaluator {
  PncReferralEvaluator._();

  static PncReferralResult evaluate({
    bool hasDangerSigns = false,
    double? systolic,
    double? diastolic,
    double? temperatureCelsius,
    int? pulseBpm,
    double? hemoglobinGdL,
    double? fastingGlucoseMmol,
    double? randomGlucoseMmol,
    String? urinaryBilirubin,
    String? urinaryAlbumin,
    String? edema,
    bool? hasKnownHtnEclampsia,
    bool? onHtnTreatment,
    bool? hasKnownDmGdm,
    bool? onDmTreatment,
  }) {
    final urgent = <String>[];
    final nonUrgent = <String>[];

    // ── Urgent conditions ─────────────────────────────────────────────────────

    if (hasDangerSigns) urgent.add('Danger signs present');

    // High BP ≥ 140/90
    final highBp = (systolic != null && systolic >= bpHighSystolic) ||
        (diastolic != null && diastolic >= bpHighDiastolic);
    if (highBp) urgent.add('High blood pressure (≥140/90)');

    // Pre-eclampsia: edema + (BP ≥ 140/90 OR albumin present)
    final albuminPresent = _isPresent(urinaryAlbumin);
    final edemaPresent = _isPresent(edema);
    if (edemaPresent && (highBp || albuminPresent)) {
      urgent.add('Suspected pre-eclampsia');
    }

    // High fever ≥ 102°F (38.9°C)
    if (temperatureCelsius != null && temperatureCelsius >= 38.9) {
      urgent.add('High fever (≥102°F)');
    }

    // Abnormal pulse: outside 60–90 bpm
    if (pulseBpm != null &&
        (pulseBpm > pulseHigh.toInt() || pulseBpm < pulseLow.toInt())) {
      urgent.add('Abnormal pulse');
    }

    // Severe anaemia: Hb < 8 g/dL
    if (hemoglobinGdL != null && hemoglobinGdL < hbSevereAnaemia) {
      urgent.add('Severe anaemia (Hb <8 g/dL)');
    }

    // High blood sugar: FBS ≥ 7.0 or RBS ≥ 11.1 mmol/L (known DM/GDM thresholds)
    final highFbs =
        fastingGlucoseMmol != null && fastingGlucoseMmol >= pncFbsHighMmol;
    final highRbs =
        randomGlucoseMmol != null && randomGlucoseMmol >= pncRbsHighMmol;
    if (highFbs || highRbs) urgent.add('High blood sugar');

    // Urinary bilirubin present
    if (_isPresent(urinaryBilirubin)) urgent.add('Urinary bilirubin present');

    // Known HTN/eclampsia NOT on treatment
    if (hasKnownHtnEclampsia == true && onHtnTreatment == false) {
      urgent.add('Untreated hypertension/eclampsia');
    }

    // Known DM/GDM NOT on treatment
    if (hasKnownDmGdm == true && onDmTreatment == false) {
      urgent.add('Untreated diabetes/GDM');
    }

    // ── Non-urgent conditions ─────────────────────────────────────────────────

    // Moderate anaemia: 8–10 g/dL
    if (hemoglobinGdL != null &&
        hemoglobinGdL >= hbSevereAnaemia &&
        hemoglobinGdL < hbModerateAnaemia) {
      nonUrgent.add('Moderate anaemia (Hb 8–10 g/dL)');
    }

    // Mild anaemia: 10–11 g/dL
    if (hemoglobinGdL != null &&
        hemoglobinGdL >= hbModerateAnaemia &&
        hemoglobinGdL < hbMildAnaemia) {
      nonUrgent.add('Mild anaemia (Hb 10–11 g/dL)');
    }

    // Mild fever: 100–101.9°F (37.8–38.8°C)
    if (temperatureCelsius != null &&
        temperatureCelsius >= 37.8 &&
        temperatureCelsius < 38.9) {
      nonUrgent.add('Mild fever (100–101.9°F)');
    }

    // Known HTN/eclampsia ON treatment
    if (hasKnownHtnEclampsia == true && onHtnTreatment == true) {
      nonUrgent.add('Hypertension on treatment');
    }

    // Known DM/GDM ON treatment
    if (hasKnownDmGdm == true && onDmTreatment == true) {
      nonUrgent.add('Diabetes on treatment');
    }

    // Suspected diabetes in women without known DM/GDM:
    // FBS ≥ 5.1 or RBS ≥ 8.5 mmol/L — Bangladesh UHIS Phase 1 spec, #3.
    if (hasKnownDmGdm != true) {
      final suspectedFbs = fastingGlucoseMmol != null &&
          fastingGlucoseMmol >= ancFbsDiabetesMmol;
      final suspectedRbs =
          randomGlucoseMmol != null && randomGlucoseMmol >= ancRbsDiabetesMmol;
      if (suspectedFbs || suspectedRbs) nonUrgent.add('Suspected diabetes (FBS≥5.1 or RBS≥8.5)');
    }

    return PncReferralResult(
      urgentConditions: urgent,
      nonUrgentConditions: nonUrgent,
    );
  }

  static bool _isPresent(String? value) {
    if (value == null) return false;
    final v = value.toLowerCase();
    return v != 'absent' && v != 'negative' && v != 'none' && v != 'no';
  }
}
