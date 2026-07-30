/// Bridges server-synced assessment history into the same synthetic map
/// shape each programme's rule function (`anc_briefing_rules.dart` etc.)
/// already expects — so those pure functions run completely unchanged
/// whether they're fed a real `local_assessments` row or history-derived
/// data.
///
/// Reuses `ClinicalVitalsFromHistory` (`lib/core/risk/clinical_vitals_from_history.dart`)
/// verbatim — the exact adapter `WorklistRepository` already relies on to
/// score risk bands from server-synced history, not a re-derivation of that
/// parsing logic.
///
/// Deliberately partial: only fields `ClinicalVitalsFromHistory` actually
/// extracts (BP, Hb, fasting glucose) are ever populated here. Danger-sign
/// specifics, IFA/Calcium consumption counts, PNC temperature/pulse, and NCD
/// medication compliance only ever existed in the original full submission —
/// the server's history rollup doesn't resend that level of detail, so
/// those specific rules simply don't fire against history-derived data.
/// Every rule function already null-checks its own fields individually, so
/// this degrades gracefully rather than crashing or fabricating a value.
library;

import '../../db/assessment_dao.dart';
import '../../models/risk.dart';
import '../../risk/clinical_vitals_from_history.dart';
import '../../../features/patient/member_detail_repository.dart';

/// Up to the 2 most recent parseable [ClinicalVitals] for [assessmentType]
/// (matched case-insensitively as a substring of `AssessmentRow.kind`, since
/// server wire strings vary — e.g. 'PNC' vs 'PNC_MOTHER' — the same
/// leniency `Programme.fromTag` already applies elsewhere in this app).
/// [rows] must already be ordered newest-first (as `AssessmentDao.forMany`
/// returns them).
List<ClinicalVitals> vitalsHistoryFor(
  List<AssessmentRow> rows,
  String assessmentType,
) {
  final needle = assessmentType.toUpperCase();
  final result = <ClinicalVitals>[];
  for (final row in rows) {
    if (!(row.kind ?? '').toUpperCase().contains(needle)) continue;
    final vitals = ClinicalVitalsFromHistory.fromRawJson(
      row.rawJson,
      assessmentType: row.kind,
    );
    if (vitals == null) continue;
    result.add(vitals);
    if (result.length >= 2) break;
  }
  return result;
}

/// Same as [vitalsHistoryFor] but for [MemberAssessment] — the shape used by
/// `PatientOrMemberData.assessments` (merged local-cache + live-fetched
/// history). Hits the same `member-assessment-history` endpoint as
/// `AssessmentDao`, so `MemberAssessment.rawJson` (already a decoded map,
/// unlike `AssessmentRow.rawJson`'s JSON string) carries the same
/// `observations` shape `ClinicalVitalsFromHistory` already parses.
/// [assessments] must already be ordered newest-first (as
/// `PatientOrMemberData.assessments` returns them).
List<ClinicalVitals> vitalsFromMemberAssessments(
  List<MemberAssessment> assessments,
  String assessmentType,
) {
  final needle = assessmentType.toUpperCase();
  final result = <ClinicalVitals>[];
  for (final a in assessments) {
    if (!a.type.toUpperCase().contains(needle)) continue;
    final vitals = ClinicalVitalsFromHistory.fromMap(
      a.rawJson,
      assessmentType: a.type,
    );
    if (vitals == null) continue;
    result.add(vitals);
    if (result.length >= 2) break;
  }
  return result;
}

Map<String, dynamic> ancMapFromVitals(ClinicalVitals vitals) => {
      if (vitals.systolicBp != null || vitals.diastolicBp != null)
        'medicalHistoryPhysicalExamination': {
          if (vitals.systolicBp != null) 'systolic': vitals.systolicBp,
          if (vitals.diastolicBp != null) 'diastolic': vitals.diastolicBp,
        },
      if (vitals.hemoglobin != null)
        'pointOfCareInvestigations': {'hemoglobin': vitals.hemoglobin},
    };

Map<String, dynamic> pncMapFromVitals(ClinicalVitals vitals) => {
      if (vitals.systolicBp != null ||
          vitals.diastolicBp != null ||
          vitals.hemoglobin != null)
        'maternalHealthAssessment': {
          if (vitals.systolicBp != null) 'systolic': vitals.systolicBp,
          if (vitals.diastolicBp != null) 'diastolic': vitals.diastolicBp,
          if (vitals.hemoglobin != null) 'hemoglobin': vitals.hemoglobin,
        },
    };

Map<String, dynamic> ncdMapFromVitals(ClinicalVitals vitals) => {
      if (vitals.systolicBp != null || vitals.diastolicBp != null)
        'bpLog': {
          if (vitals.systolicBp != null) 'avgSystolic': vitals.systolicBp,
          if (vitals.diastolicBp != null) 'avgDiastolic': vitals.diastolicBp,
        },
      // ClinicalVitalsFromHistory only ever captures FASTING glucose — a
      // random reading from history is not recoverable via this adapter.
      if (vitals.fastingGlucoseMmolL != null)
        'glucoseLog': {
          'glucoseValue': vitals.fastingGlucoseMmolL,
          'glucoseType': 'fbs',
        },
    };
