/// Deterministic PNC (mother) clinical findings for the "Before You Knock"
/// briefing. Pure function — reads directly from the raw
/// `local_assessments.assessment_details` JSON produced by
/// `UnifiedPayloadMapper._toPncMother` (systolic/diastolic/pulse are
/// strings; temperature is stored in °F directly).
library;

import '../../../features/visit/forms/form_config.dart';
import '../assessment_thresholds.dart';
import '../referral_evaluator.dart';
import '../../constants/app_strings.dart';
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
      message: ClinicalFindingStrings.dangerSignReported(_resolveOptionLabel(code)),
      programme: 'pnc',
    ));
  }
  if (codedSigns.isEmpty) {
    for (final fieldId in _booleanDangerSignFields) {
      if (maternal?[fieldId] == true || maternal?[fieldId] == 'Yes') {
        findings.add(ClinicalFinding(
          code: 'pnc.dangerSign',
          message: ClinicalFindingStrings.dangerSignReported(_titleCase(fieldId)),
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
    findings.add(ClinicalFinding(
      code: 'pnc.urgentTemperature',
      message: ClinicalFindingStrings.pncUrgentTemperature,
      programme: 'pnc',
    ));
  }
  if (pulse != null && (pulse > pulseHigh || pulse < pulseLow)) {
    findings.add(ClinicalFinding(
      code: 'pnc.urgentPulse',
      message: ClinicalFindingStrings.pncUrgentPulse,
      programme: 'pnc',
    ));
  }
  if ((systolic != null && systolic >= bpHighSystolic) ||
      (diastolic != null && diastolic >= bpHighDiastolic)) {
    findings.add(ClinicalFinding(
      code: 'pnc.urgentBp',
      message: ClinicalFindingStrings.pncUrgentBp,
      programme: 'pnc',
    ));
  }

  // ── Hb < 8 ──
  final hb = _num(maternal?['hemoglobin']);
  if (hb != null && hb < hbSevereAnaemia) {
    findings.add(ClinicalFinding(
      code: 'pnc.severeAnaemia',
      message: ClinicalFindingStrings.pncSevereAnemia,
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
    if (gap.contains('No contraception') ||
        gap.contains('postpartum contraception')) {
      findings.add(ClinicalFinding(
        code: 'pnc.noContraception',
        message: ClinicalFindingStrings.pncNoContraception,
        programme: 'pnc',
      ));
    } else if (gap.contains('Vitamin A')) {
      findings.add(ClinicalFinding(
        code: 'pnc.supplementGapVitaminA',
        message: ClinicalFindingStrings.pncSupplementGapVitaminA,
        programme: 'pnc',
      ));
    } else if (gap.contains('IFA')) {
      findings.add(ClinicalFinding(
        code: 'pnc.supplementGapIfa',
        message: ClinicalFindingStrings.pncSupplementGapIfa,
        programme: 'pnc',
      ));
    } else if (gap.contains('Calcium')) {
      findings.add(ClinicalFinding(
        code: 'pnc.supplementGapCalcium',
        message: ClinicalFindingStrings.pncSupplementGapCalcium,
        programme: 'pnc',
      ));
    }
  }

  // ── PNC visit overdue ──
  if (overdueDaysOverdue != null) {
    findings.add(ClinicalFinding(
      code: 'pnc.overdueVisit',
      message: ClinicalFindingStrings.pncOverdueVisit(pncVisitCount + 1, overdueDaysOverdue),
      programme: 'pnc',
    ));
  }

  // ── Routine fallback ──
  if (findings.isEmpty) {
    findings.add(ClinicalFinding(
      code: 'pnc.routine',
      message: ClinicalFindingStrings.pncRoutine,
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
