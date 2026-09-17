/// Dispatches per-programme clinical-findings rule functions for the
/// "Before You Knock" briefing and merges their results into one flat list.
///
/// This is the ONLY file in `briefing_rules/` that touches the DB — every
/// rule function it calls (`anc_briefing_rules.dart` etc.) is a pure
/// function, so all repository/DAO reads live here.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;

import '../../db/assessment_dao.dart';
import '../../db/immunisation_dao.dart';
import '../../db/local_assessment_dao.dart';
import '../../db/member_dao.dart';
import '../../db/patient_dao.dart';
import '../../models/programme.dart';
import '../../../features/household/member_assessment_lookup.dart';
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
    // Resolves every id a member's assessment rows may be keyed under (route
    // id, `patients.id`, `patients.patient_id`, member fhir/patient/reference
    // ids). Optional: without it this falls back to the route id plus the
    // remapped `patientCtx.patientId`, which is strictly better than the
    // single route id but still misses rows stored under a server patient id
    // the route didn't carry.
    MemberDao? memberDao,
    // Third fallback tier — `PatientOrMemberData.assessments` (merged
    // local-cache + live-fetched history) for a patient this device hasn't
    // locally synced yet. Only consulted when local rows AND
    // `historyAssessmentDao` both come back empty for a programme.
    List<MemberAssessment> remoteAssessments = const [],
  }) async {
    final findings = <ClinicalFinding>[];

    // Assessment rows are not all keyed by the id a screen routes with, so a
    // single-key read silently reports "no visits" for a patient who has
    // several — which surfaced as a routine finding announcing "Visit 1" for a
    // woman on her third ANC. Resolve the full candidate key set once and use
    // it for every read below.
    final lookupKeys = await _lookupKeysFor(
      routePatientId: patientId,
      contextPatientId: patientCtx.patientId,
      patientDao: patientDao,
      memberDao: memberDao,
    );

    final allRows = await assessmentDao.getByPatientIds(lookupKeys);
    final followUps = await followUpRepo.openForPatientLocal(patientId);
    // Only fetched lazily (see _historyRows) — most patients with real local
    // history never need this second query at all.
    List<AssessmentRow>? historyRows;
    Future<List<AssessmentRow>> loadHistoryRows() async {
      if (historyRows != null) return historyRows!;
      final byKey = await historyAssessmentDao.forMany(lookupKeys);
      final merged = <String, AssessmentRow>{};
      for (final key in lookupKeys) {
        for (final row in byKey[key] ?? const <AssessmentRow>[]) {
          merged[row.id] = row;   // de-dup: keys may resolve to one member
        }
      }
      historyRows = merged.values.toList()
        ..sort((a, b) => (b.occurredAt ?? 0).compareTo(a.occurredAt ?? 0));
      return historyRows!;
    }

    if (selectedProgrammes.contains(Programme.anc)) {
      final ancRows = _rowsOfType(allRows, 'ANC');
      final missedDays = _daysOverdueFor(followUps, 'ANC');
      var latest = _detailsAt(ancRows, 0);
      var previous = _detailsAt(ancRows, 1);
      // Counted from whichever tier actually supplied [latest] — never from a
      // different one. Local rows are the only tier `ancRows` sees, so a
      // history- or remote-derived latest previously always reported 0.
      var visitCount = ancRows.length;
      if (latest == null) {
        final rows = await loadHistoryRows();
        final vitals = vitalsHistoryFor(rows, 'ANC');
        if (vitals.isNotEmpty) {
          latest = ancMapFromVitals(vitals[0]);
          visitCount = _historyCountOfKind(rows, 'ANC');
        }
        if (vitals.length > 1) previous = ancMapFromVitals(vitals[1]);
      }
      if (latest == null) {
        final vitals = vitalsFromMemberAssessments(remoteAssessments, 'ANC');
        if (vitals.isNotEmpty) {
          latest = ancMapFromVitals(vitals[0]);
          visitCount = _remoteCountOfType(remoteAssessments, 'ANC');
        }
        if (vitals.length > 1) previous = ancMapFromVitals(vitals[1]);
      }
      findings.addAll(evaluateAncFindings(
        latest: latest,
        previous: previous,
        ancVisitCount: visitCount,
        hasKnownHypertension: patientCtx.hasKnownHypertension,
        missedVisitDaysOverdue: missedDays,
      ));
    }

    if (selectedProgrammes.contains(Programme.pnc)) {
      final pncRows = _rowsOfType(allRows, 'PNC_MOTHER');
      final overdueDays = _daysOverdueFor(followUps, 'PNC');
      var latest = _detailsAt(pncRows, 0);
      var visitCount = pncRows.length;   // see the ANC branch's note above
      if (latest == null) {
        final rows = await loadHistoryRows();
        final vitals = vitalsHistoryFor(rows, 'PNC');
        if (vitals.isNotEmpty) {
          latest = pncMapFromVitals(vitals[0]);
          visitCount = _historyCountOfKind(rows, 'PNC');
        }
      }
      if (latest == null) {
        final vitals = vitalsFromMemberAssessments(remoteAssessments, 'PNC');
        if (vitals.isNotEmpty) {
          latest = pncMapFromVitals(vitals[0]);
          visitCount = _remoteCountOfType(remoteAssessments, 'PNC');
        }
      }
      findings.addAll(evaluatePncFindings(
        latest: latest,
        pncVisitCount: visitCount,
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

    if (patientCtx.isYoungChild || selectedProgrammes.contains(Programme.imci)) {
      // Deliberately uses patientCtx.patientId (the already-remapped local
      // `patients.id`) rather than the raw `patientId` parameter above: the
      // `patients` and `immunisations` tables this branch reads are keyed
      // strictly by the local id, unlike local_assessments/assessments/
      // follow_ups (which tolerate the FHIR-shaped id once synced). Passing
      // an un-remapped FHIR id here silently zeroes out every child
      // immunization finding — see PatientDao.byId's lack of a byAnyId-style
      // fallback.
      //
      // `allRows` (fetched above with the raw `patientId`) has the same
      // problem for the EPI rows this branch reads to compute
      // weightGainSlowed: if a patient's EPI assessments were persisted
      // under the local id while `patientId` is still the FHIR id, `allRows`
      // won't contain them. Re-fetch under patientCtx.patientId whenever the
      // two ids differ instead of reusing allRows as-is.
      // `allRows` is now read across the full key set (which includes
      // patientCtx.patientId), so the separate re-fetch this branch used to
      // need is redundant.
      final childRows = allRows;
      findings.addAll(await _evaluateChildImmunization(
        patientId: patientCtx.patientId,
        allRows: childRows,
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

  /// Every id under which this member's assessment rows may be stored.
  ///
  /// Delegates to [assessmentLookupKeysForRoute] when a [MemberDao] is
  /// available so the set matches what the rest of the patient screen already
  /// resolves; otherwise falls back to the two ids this aggregator can derive
  /// on its own.
  static Future<List<String>> _lookupKeysFor({
    required String routePatientId,
    required String contextPatientId,
    required PatientDao patientDao,
    required MemberDao? memberDao,
  }) async {
    if (memberDao != null) {
      try {
        final keys = await assessmentLookupKeysForRoute(
          routePatientId: routePatientId,
          memberDao: memberDao,
          patientDao: patientDao,
        );
        if (keys.isNotEmpty) return keys.toList();
      } on Object catch (e) {
        // Non-fatal — fall through to the derivable pair below rather than
        // losing every finding to a lookup failure.
        debugPrint('[BriefingFindings] lookup-key resolution failed: $e');
      }
    }
    return <String>{routePatientId, contextPatientId}
        .map((k) => k.trim())
        .where((k) => k.isNotEmpty)
        .toList();
  }

  /// Synced history rows for [assessmentType], matched the same lenient way
  /// [vitalsHistoryFor] matches them (substring, case-insensitive) so the
  /// count and the vitals always describe the same set of visits.
  static int _historyCountOfKind(
    List<AssessmentRow> rows,
    String assessmentType,
  ) {
    final needle = assessmentType.toUpperCase();
    return rows
        .where((r) => (r.kind ?? '').toUpperCase().contains(needle))
        .length;
  }

  /// [MemberAssessment] counterpart of [_historyCountOfKind] — mirrors
  /// [vitalsFromMemberAssessments]'s matching.
  static int _remoteCountOfType(
    List<MemberAssessment> assessments,
    String assessmentType,
  ) {
    final needle = assessmentType.toUpperCase();
    return assessments
        .where((a) => a.type.toUpperCase().contains(needle))
        .length;
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
