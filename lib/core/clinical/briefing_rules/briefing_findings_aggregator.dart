/// Dispatches per-programme clinical-findings rule functions for the
/// "Before You Knock" briefing and merges their results into one flat list.
///
/// This is the ONLY file in `briefing_rules/` that touches the DB — every
/// rule function it calls (`anc_briefing_rules.dart` etc.) is a pure
/// function, so all repository/DAO reads live here.
library;

import 'dart:convert';

import '../../db/assessment_dao.dart';
import '../../db/immunisation_dao.dart';
import '../../db/local_assessment_dao.dart';
import '../../db/patient_dao.dart';
import '../../models/programme.dart';
import '../../../features/patient/followup_repository.dart';
import '../../../features/patient/member_detail_repository.dart';
import '../../../features/visit/immunisation/epi_schedule_engine.dart';
import '../../../features/visit/triage/patient_context_builder.dart';
import 'anc_briefing_rules.dart';
import 'child_immunization_briefing_rules.dart';
import 'clinical_finding.dart';
import 'clinical_vitals_history_adapter.dart';
import 'ncd_briefing_rules.dart';
import 'pnc_briefing_rules.dart';
import 'pregnancy_outcome_briefing_rules.dart';

class BriefingFindingsAggregator {
  BriefingFindingsAggregator._();

  static Future<List<ClinicalFinding>> build({
    required String patientId,
    required PatientContext patientCtx,
    required Set<Programme> selectedProgrammes,
    required LocalAssessmentDao assessmentDao,
    required AssessmentDao historyAssessmentDao,
    required FollowUpRepository followUpRepo,
    required PatientDao patientDao,
    required ImmunisationDao immunisationDao,
    // Third fallback tier — `PatientOrMemberData.assessments` (merged
    // local-cache + live-fetched history) for a patient this device hasn't
    // locally synced yet. Only consulted when local rows AND
    // `historyAssessmentDao` both come back empty for a programme.
    List<MemberAssessment> remoteAssessments = const [],
  }) async {
    final findings = <ClinicalFinding>[];

    final allRows = await assessmentDao.getByPatientId(patientId);
    final followUps = await followUpRepo.openForPatientLocal(patientId);
    // Only fetched lazily (see _historyRows) — most patients with real local
    // history never need this second query at all.
    List<AssessmentRow>? historyRows;
    Future<List<AssessmentRow>> loadHistoryRows() async {
      if (historyRows != null) return historyRows!;
      final byPatient = await historyAssessmentDao.forMany([patientId]);
      historyRows = byPatient[patientId] ?? const <AssessmentRow>[];
      return historyRows!;
    }

    if (selectedProgrammes.contains(Programme.anc)) {
      final ancRows = _rowsOfType(allRows, 'ANC');
      final missedDays = _daysOverdueFor(followUps, 'ANC');
      var latest = _detailsAt(ancRows, 0);
      var previous = _detailsAt(ancRows, 1);
      if (latest == null) {
        final vitals = vitalsHistoryFor(await loadHistoryRows(), 'ANC');
        if (vitals.isNotEmpty) latest = ancMapFromVitals(vitals[0]);
        if (vitals.length > 1) previous = ancMapFromVitals(vitals[1]);
      }
      if (latest == null) {
        final vitals = vitalsFromMemberAssessments(remoteAssessments, 'ANC');
        if (vitals.isNotEmpty) latest = ancMapFromVitals(vitals[0]);
        if (vitals.length > 1) previous = ancMapFromVitals(vitals[1]);
      }
      findings.addAll(evaluateAncFindings(
        latest: latest,
        previous: previous,
        ancVisitCount: ancRows.length,
        hasKnownHypertension: patientCtx.hasKnownHypertension,
        missedVisitDaysOverdue: missedDays,
      ));
    }

    if (selectedProgrammes.contains(Programme.pnc)) {
      final pncRows = _rowsOfType(allRows, 'PNC_MOTHER');
      final overdueDays = _daysOverdueFor(followUps, 'PNC');
      var latest = _detailsAt(pncRows, 0);
      if (latest == null) {
        final vitals = vitalsHistoryFor(await loadHistoryRows(), 'PNC');
        if (vitals.isNotEmpty) latest = pncMapFromVitals(vitals[0]);
      }
      if (latest == null) {
        final vitals = vitalsFromMemberAssessments(remoteAssessments, 'PNC');
        if (vitals.isNotEmpty) latest = pncMapFromVitals(vitals[0]);
      }
      findings.addAll(evaluatePncFindings(
        latest: latest,
        pncVisitCount: pncRows.length,
        overdueDaysOverdue: overdueDays,
      ));
    }

    if (selectedProgrammes.contains(Programme.ncd)) {
      final ncdRows = _rowsOfType(allRows, 'NCD');
      var latest = _detailsAt(ncdRows, 0);
      var previous = _detailsAt(ncdRows, 1);
      if (latest == null) {
        final vitals = vitalsHistoryFor(await loadHistoryRows(), 'NCD');
        if (vitals.isNotEmpty) latest = ncdMapFromVitals(vitals[0]);
        if (vitals.length > 1) previous = ncdMapFromVitals(vitals[1]);
      }
      if (latest == null) {
        final vitals = vitalsFromMemberAssessments(remoteAssessments, 'NCD');
        if (vitals.isNotEmpty) latest = ncdMapFromVitals(vitals[0]);
        if (vitals.length > 1) previous = ncdMapFromVitals(vitals[1]);
      }
      findings.addAll(evaluateNcdFindings(
        latest: latest,
        previous: previous,
        hasKnownHypertension: patientCtx.hasKnownHypertension,
        hasKnownDiabetes: patientCtx.hasKnownDiabetes,
      ));
    }

    // Gated independently of selectedProgrammes — Programme.fromTag folds
    // 'PREGNANCY_OUTCOME' into the same Programme.pnc bucket as ordinary PNC,
    // so only isPostpartum + a real delivery date can distinguish a genuine
    // delivery-outcome visit.
    if (patientCtx.isPostpartum && patientCtx.deliveryDateMillis != null) {
      final outcomeRows = _rowsOfType(allRows, 'PREGNANCY_OUTCOME');
      findings.addAll(evaluatePregnancyOutcomeFindings(
        latest: _detailsAt(outcomeRows, 0),
      ));
    }

    if (patientCtx.isUnder5 || selectedProgrammes.contains(Programme.imci)) {
      findings.addAll(await _evaluateChildImmunization(
        patientId: patientId,
        allRows: allRows,
        patientDao: patientDao,
        immunisationDao: immunisationDao,
      ));
    }

    return findings;
  }

  static Future<List<ClinicalFinding>> _evaluateChildImmunization({
    required String patientId,
    required List<LocalAssessmentEntity> allRows,
    required PatientDao patientDao,
    required ImmunisationDao immunisationDao,
  }) async {
    final patient = await patientDao.byId(patientId);
    final dobStr = patient?.dob;
    if (dobStr == null || dobStr.isEmpty) return const [];
    final dob = DateTime.tryParse(dobStr);
    if (dob == null) return const [];

    final rowsByPatient = await immunisationDao.forMany([patientId]);
    final immunisationRows = rowsByPatient[patientId] ?? const <ImmunisationRow>[];
    final milestones = await EpiScheduleEngine.build(
      dob: dob,
      rows: immunisationRows,
    );

    final epiRows = _rowsOfType(allRows, 'EPI');
    final weights = <double>[];
    for (final row in epiRows) {
      final details = _decode(row.assessmentDetails);
      final weightKg = details?['weightKg'];
      final parsed = weightKg is num
          ? weightKg.toDouble()
          : (weightKg is String ? double.tryParse(weightKg) : null);
      if (parsed != null) weights.add(parsed);
      if (weights.length >= 2) break;
    }

    return evaluateChildImmunizationFindings(
      milestones: milestones,
      latestWeightKg: weights.isNotEmpty ? weights[0] : null,
      previousWeightKg: weights.length > 1 ? weights[1] : null,
    );
  }

  static List<LocalAssessmentEntity> _rowsOfType(
    List<LocalAssessmentEntity> rows,
    String assessmentType,
  ) =>
      rows.where((r) => r.assessmentType.toUpperCase() == assessmentType).toList();

  static Map<String, dynamic>? _detailsAt(
    List<LocalAssessmentEntity> rows,
    int index,
  ) {
    if (index >= rows.length) return null;
    return _decode(rows[index].assessmentDetails);
  }

  static Map<String, dynamic>? _decode(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map<String, dynamic>) return decoded;
      return null;
    } on Object {
      return null;
    }
  }

  static int? _daysOverdueFor(List<FollowUp> followUps, String programmeSubstring) {
    final match = followUps
        .where((f) =>
            f.isOverdue &&
            (f.programme?.toUpperCase().contains(programmeSubstring) ?? false))
        .toList();
    if (match.isEmpty) return null;
    match.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    return DateTime.now().difference(match.first.dueDate).inDays;
  }
}
