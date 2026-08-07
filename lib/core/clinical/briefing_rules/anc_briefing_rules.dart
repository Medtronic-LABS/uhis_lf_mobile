/// Deterministic ANC clinical findings for the "Before You Knock" briefing.
///
/// Pure function — no Flutter/DB dependencies, matching the convention in
/// `referral_evaluator.dart`. Reads directly from the raw
/// `local_assessments.assessment_details` JSON map (NOT via `AncAssessment
/// .fromJson()` — that model's `MedicalHistoryPhysicalExamination.fromJson`
/// expects `bloodPressureSystolic`/`bloodPressureDiastolic`/`oedema` keys,
/// but the real stored payload (`UnifiedPayloadMapper._toAnc`) writes
/// `systolic`/`diastolic`/`edema` instead — reading the raw map directly
/// avoids that mismatch entirely).
library;

import '../../../features/visit/forms/form_config.dart';
import '../assessment_thresholds.dart';
import '../referral_evaluator.dart';
import '../../constants/app_strings.dart';
import 'clinical_finding.dart';

const _ancDangerSignFieldIds = [
  'dangerSignsExperienced12',
  'dangerSignsExperienced13To27',
  'dangerSignsExperienced28To40',
];

List<ClinicalFinding> evaluateAncFindings({
  required Map<String, dynamic>? latest,
  required Map<String, dynamic>? previous,
  required int ancVisitCount,
  required bool hasKnownHypertension,
  int? missedVisitDaysOverdue,
}) {
  if (latest == null) return const [];

  final medHx = (latest['medicalHistoryPhysicalExamination'] as Map?)
      ?.cast<String, dynamic>();
  final poci = (latest['pointOfCareInvestigations'] as Map?)
      ?.cast<String, dynamic>();
  final dangerSigns = (latest['dangerSignsRiskIdentification'] as Map?)
      ?.cast<String, dynamic>();
  final vaccination = (latest['vaccinationAndSupplements'] as Map?)
      ?.cast<String, dynamic>();

  final findings = <ClinicalFinding>[];

  // ── Danger signs — one finding per sign, human-readable label ──
  // Skip Spice "None" tokens (≤12 → id 6; 13–40 → id 7; legacy "none").
  for (final fieldId in _ancDangerSignFieldIds) {
    final noneId = fieldId == 'dangerSignsExperienced12' ? '6' : '7';
    final codes = (dangerSigns?[fieldId] as List?)?.cast<String>() ?? const [];
    for (final code in codes) {
      final token = code.trim().toLowerCase();
      if (token.isEmpty || token == 'none' || token == noneId) continue;
      final label = _resolveOptionLabel(_ancDangerSignFieldIds, code);
      findings.add(ClinicalFinding(
        code: 'anc.dangerSign',
        message: ClinicalFindingStrings.dangerSignReported(label),
        programme: 'anc',
      ));
    }
  }

  // ── BP ≥140/90 or known HTN ──
  final systolic = _num(medHx?['systolic']);
  final diastolic = _num(medHx?['diastolic']);
  final highBp = (systolic != null && systolic >= bpHighSystolic) ||
      (diastolic != null && diastolic >= bpHighDiastolic) ||
      hasKnownHypertension;
  if (highBp) {
    findings.add(ClinicalFinding(
      code: 'anc.highBp',
      message: ClinicalFindingStrings.ancBpAboveSafeThreshold,
      programme: 'anc',
    ));
  } else {
    // ── BP rising trend, only when not already over threshold ──
    final prevMedHx = (previous?['medicalHistoryPhysicalExamination'] as Map?)
        ?.cast<String, dynamic>();
    final prevSystolic = _num(prevMedHx?['systolic']);
    if (systolic != null && prevSystolic != null && systolic > prevSystolic) {
      findings.add(ClinicalFinding(
        code: 'anc.bpRisingTrend',
        message: ClinicalFindingStrings.ancBpRisingTwoVisits,
        programme: 'anc',
      ));
    }
  }

  // ── Hb bands ──
  final hb = _num(poci?['hemoglobin']);
  if (hb != null) {
    if (hb < hbSevereAnaemia) {
      findings.add(ClinicalFinding(
        code: 'anc.severeAnaemia',
        message: ClinicalFindingStrings.pncSevereAnemia,
        programme: 'anc',
      ));
    } else if (hb <= 10.9) {
      findings.add(ClinicalFinding(
        code: 'anc.anaemiaNoted',
        message: ClinicalFindingStrings.ancAnemiaReinforceIron,
        programme: 'anc',
      ));
    }
  }

  // ── IFA/Calcium consumption below expected rate ──
  final gaps = AncReferralEvaluator.evaluateGaps(
    ifaTotalConsumed: _int(vaccination?['ifaTotalConsumed']),
    calciumTotalConsumed: _int(vaccination?['calciumTotalConsumed']),
  );
  final hasSupplementGap = gaps.gaps.any((g) =>
      g.contains('IFA consumption') || g.contains('Calcium consumption'));
  if (hasSupplementGap) {
    findings.add(ClinicalFinding(
      code: 'anc.supplementGap',
      message: ClinicalFindingStrings.ancIronFolicBelowExpected,
      programme: 'anc',
    ));
  }

  // ── Missed ANC visit ──
  if (missedVisitDaysOverdue != null) {
    findings.add(ClinicalFinding(
      code: 'anc.missedVisit',
      message: ClinicalFindingStrings.ancMissedVisit(missedVisitDaysOverdue),
      programme: 'anc',
    ));
  }

  // ── Routine fallback ──
  if (findings.isEmpty) {
    findings.add(ClinicalFinding(
      code: 'anc.routine',
      message: ClinicalFindingStrings.ancRoutineVisit(ancVisitCount + 1),
      programme: 'anc',
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

int? _int(dynamic v) {
  final n = _num(v);
  return n?.toInt();
}

/// Resolves a danger-sign option code to its human-readable label by
/// checking each trimester-specific field's option list (a code only
/// appears in one of the three) — falls back to the raw code if
/// `FormConfig` isn't loaded or the code isn't found in any of them.
String _resolveOptionLabel(List<String> candidateFieldIds, String code) {
  try {
    final fields = FormConfig.instance.fields;
    for (final fieldId in candidateFieldIds) {
      final options = fields[fieldId]?.options ?? const [];
      final option = FieldOption.find(code, options);
      if (option != null) return option.displayName;
    }
  } on Object {
    // FormConfig not loaded yet — degrade to the raw code rather than throw.
  }
  return code;
}
