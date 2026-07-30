/// Deterministic PNC (mother) clinical findings for the "Before You Knock"
/// briefing. Pure function — reads directly from the raw
/// `local_assessments.assessment_details` JSON produced by
/// `UnifiedPayloadMapper._toPncMother` (systolic/diastolic/pulse are
/// strings; temperature is stored in °F directly).
library;

import '../../../features/visit/forms/form_config.dart';
import '../assessment_thresholds.dart';
import '../referral_evaluator.dart';
import 'clinical_finding.dart';

const _postpartumDangerSignsFieldId = 'postpartumDangerSigns';
const _booleanDangerSignFields = [
  'heavyBleeding',
  'foulSmellDischarge',
  'severeAbdominalPain',
  'difficultyBreathing',
  'convulsions',
  'unconsciousness',
];

List<ClinicalFinding> evaluatePncFindings({
  required Map<String, dynamic>? latest,
  required int pncVisitCount,
  int? overdueDaysOverdue,
}) {
  if (latest == null) return const [];

  final maternal =
      (latest['maternalHealthAssessment'] as Map?)?.cast<String, dynamic>();
  final contraception = (latest['postpartumContraception'] as Map?)
      ?.cast<String, dynamic>();

  final findings = <ClinicalFinding>[];

  // ── Danger signs — coded list, plus fallback boolean fields for older records ──
  final codedSigns =
      (maternal?[_postpartumDangerSignsFieldId] as List?)?.cast<String>() ??
          const [];
  for (final code in codedSigns) {
    findings.add(ClinicalFinding(
      code: 'pnc.dangerSign',
      message: 'Danger sign reported: ${_resolveOptionLabel(code)}.',
      programme: 'pnc',
    ));
  }
  if (codedSigns.isEmpty) {
    for (final fieldId in _booleanDangerSignFields) {
      if (maternal?[fieldId] == true || maternal?[fieldId] == 'Yes') {
        findings.add(ClinicalFinding(
          code: 'pnc.dangerSign',
          message: 'Danger sign reported: ${_titleCase(fieldId)}.',
          programme: 'pnc',
        ));
      }
    }
  }

  // ── Urgent vitals — named individually, not just a combined boolean ──
  final systolic = _num(maternal?['systolic']);
  final diastolic = _num(maternal?['diastolic']);
  final pulse = _num(maternal?['pulse']);
  final temperatureF = _num(maternal?['temperature']);

  if (temperatureF != null && temperatureF >= tempHighFeverF) {
    findings.add(const ClinicalFinding(
      code: 'pnc.urgentTemperature',
      message: 'Temperature is above normal (≥102°F). Needs urgent attention.',
      programme: 'pnc',
    ));
  }
  if (pulse != null && (pulse > pulseHigh || pulse < pulseLow)) {
    findings.add(const ClinicalFinding(
      code: 'pnc.urgentPulse',
      message: 'Pulse is abnormal (outside 60–90 bpm). Needs urgent attention.',
      programme: 'pnc',
    ));
  }
  if ((systolic != null && systolic >= bpHighSystolic) ||
      (diastolic != null && diastolic >= bpHighDiastolic)) {
    findings.add(const ClinicalFinding(
      code: 'pnc.urgentBp',
      message: 'BP is above normal (≥140/90). Needs urgent attention.',
      programme: 'pnc',
    ));
  }

  // ── Hb < 8 ──
  final hb = _num(maternal?['hemoglobin']);
  if (hb != null && hb < hbSevereAnaemia) {
    findings.add(const ClinicalFinding(
      code: 'pnc.severeAnaemia',
      message: 'Severe anemia.',
      programme: 'pnc',
    ));
  }

  // ── Contraception + supplement gaps (reuses PncReferralEvaluator.evaluateGaps) ──
  final gaps = PncReferralEvaluator.evaluateGaps(
    vitaminAConsumed: _boolOrNull(maternal?['vitaminAConsumed']),
    daysSinceDelivery: _int(latest['daysSinceDelivery']),
    ifaTabletsConsumed: _int(maternal?['ifaTabletsConsumed']),
    calciumTabletsConsumed: _int(maternal?['calciumTabletsConsumed']),
    familyPlanningMethod: contraception?['familyPlanningMethods'] as String?,
  );
  for (final gap in gaps.gaps) {
    if (gap.contains('No contraception method')) {
      findings.add(const ClinicalFinding(
        code: 'pnc.noContraception',
        message: 'No contraception method in use — counsel on options.',
        programme: 'pnc',
      ));
    } else if (gap.contains('Vitamin A')) {
      findings.add(const ClinicalFinding(
        code: 'pnc.supplementGapVitaminA',
        message: 'Supplement gap — Vitamin A not on track.',
        programme: 'pnc',
      ));
    } else if (gap.contains('IFA')) {
      findings.add(const ClinicalFinding(
        code: 'pnc.supplementGapIfa',
        message: 'Supplement gap — Iron-folic acid not on track.',
        programme: 'pnc',
      ));
    } else if (gap.contains('Calcium')) {
      findings.add(const ClinicalFinding(
        code: 'pnc.supplementGapCalcium',
        message: 'Supplement gap — Calcium not on track.',
        programme: 'pnc',
      ));
    }
  }

  // ── PNC visit overdue ──
  if (overdueDaysOverdue != null) {
    findings.add(ClinicalFinding(
      code: 'pnc.overdueVisit',
      message: 'PNC Visit ${pncVisitCount + 1} is overdue by $overdueDaysOverdue days.',
      programme: 'pnc',
    ));
  }

  // ── Routine fallback ──
  if (findings.isEmpty) {
    findings.add(const ClinicalFinding(
      code: 'pnc.routine',
      message: 'Recovering well — no concerns at this PNC visit.',
      programme: 'pnc',
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

bool? _boolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  final s = v.toString().toLowerCase();
  if (s == 'yes' || s == 'true') return true;
  if (s == 'no' || s == 'false') return false;
  return null;
}

String _resolveOptionLabel(String code) {
  try {
    final options =
        FormConfig.instance.fields[_postpartumDangerSignsFieldId]?.options ??
            const [];
    final option = FieldOption.find(code, options);
    if (option != null) return option.displayName;
  } on Object {
    // FormConfig not loaded yet — degrade to the raw code rather than throw.
  }
  return code;
}

String _titleCase(String camelCase) {
  final withSpaces = camelCase.replaceAllMapped(
    RegExp('([A-Z])'),
    (m) => ' ${m.group(1)}',
  );
  final trimmed = withSpaces.trim();
  if (trimmed.isEmpty) return trimmed;
  return trimmed[0].toUpperCase() + trimmed.substring(1);
}
