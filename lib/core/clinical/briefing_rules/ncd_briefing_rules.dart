/// Deterministic NCD clinical findings for the "Before You Knock" briefing.
/// Pure function — reads directly from the raw
/// `local_assessments.assessment_details` JSON produced by
/// `UnifiedPayloadMapper._toNcd`.
///
/// Deliberately does NOT reuse `NcdReferralEvaluator` — its 4-band
/// (green/yellowLow/yellowHigh/orange/red) risk classification doesn't
/// cleanly un-blend into this rule table's "BP alone / glucose alone / both
/// combined" structure, so this writes fresh boolean checks against the same
/// constants the evaluator already uses.
library;

import '../assessment_thresholds.dart';
import 'clinical_finding.dart';

List<ClinicalFinding> evaluateNcdFindings({
  required Map<String, dynamic>? latest,
  required Map<String, dynamic>? previous,
  required bool hasKnownHypertension,
  required bool hasKnownDiabetes,
}) {
  if (latest == null) return const [];

  final bpLog = (latest['bpLog'] as Map?)?.cast<String, dynamic>();
  final glucoseLog = (latest['glucoseLog'] as Map?)?.cast<String, dynamic>();
  final symptomsLog = (latest['symptomsLog'] as Map?)?.cast<String, dynamic>();

  final systolic = _num(bpLog?['avgSystolic']);
  final diastolic = _num(bpLog?['avgDiastolic']);
  final bpHigh = hasKnownHypertension ||
      (systolic != null && systolic >= bpHighSystolic) ||
      (diastolic != null && diastolic >= bpHighDiastolic);

  final glucoseValue = _num(glucoseLog?['glucoseValue']);
  final glucoseType = glucoseLog?['glucoseType'] as String?;
  final isFasting = glucoseType == 'fbs';
  final glucoseHigh = hasKnownDiabetes ||
      (glucoseValue != null &&
          (isFasting
              ? glucoseValue >= ncdControlledFbsMax
              : glucoseValue >= ncdUncontrolledRbs));

  final findings = <ClinicalFinding>[];

  if (bpHigh && glucoseHigh) {
    findings.add(const ClinicalFinding(
      code: 'ncd.bpAndGlucoseCombined',
      message: 'Both BP and blood sugar are above target — needs review today and planned follow-up.',
      programme: 'ncd',
    ));
  } else if (bpHigh) {
    findings.add(const ClinicalFinding(
      code: 'ncd.bpAlone',
      message: 'BP is above normal. Requires review and follow-up.',
      programme: 'ncd',
    ));
  } else if (glucoseHigh) {
    findings.add(const ClinicalFinding(
      code: 'ncd.glucoseAlone',
      message: 'Blood sugar is elevated. Requires review and follow-up.',
      programme: 'ncd',
    ));
  } else {
    // Not currently elevated — check for a reassuring trend before the
    // generic "within target" fallback.
    final prevBpLog = (previous?['bpLog'] as Map?)?.cast<String, dynamic>();
    final prevGlucoseLog =
        (previous?['glucoseLog'] as Map?)?.cast<String, dynamic>();
    final prevSystolic = _num(prevBpLog?['avgSystolic']);
    final prevGlucoseValue = _num(prevGlucoseLog?['glucoseValue']);

    final bpTrendingDown =
        systolic != null && prevSystolic != null && systolic < prevSystolic;
    final glucoseTrendingDown = glucoseValue != null &&
        prevGlucoseValue != null &&
        glucoseValue < prevGlucoseValue;

    if (bpTrendingDown || glucoseTrendingDown) {
      findings.add(const ClinicalFinding(
        code: 'ncd.trendingDown',
        message: 'BP/sugar trending down — continue current plan.',
        programme: 'ncd',
      ));
    } else {
      findings.add(const ClinicalFinding(
        code: 'ncd.withinTarget',
        message: 'Vitals within target — continue current management.',
        programme: 'ncd',
      ));
    }
  }

  // ── Medication adherence — approximated via the raw Yes/No compliance
  // field (no percentage-based adherence tracking exists yet); independent
  // of the BP/glucose branch above, since poor adherence can co-occur with
  // any vitals state. ──
  if (symptomsLog?['compliance'] == 'No') {
    findings.add(const ClinicalFinding(
      code: 'ncd.lowAdherence',
      message: 'Medication adherence is low — confirm daily intake.',
      programme: 'ncd',
    ));
  }

  return findings;
}

num? _num(dynamic v) {
  if (v == null) return null;
  if (v is num) return v;
  if (v is String) return num.tryParse(v);
  return null;
}
