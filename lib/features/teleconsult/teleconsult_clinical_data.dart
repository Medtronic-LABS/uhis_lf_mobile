/// Assembles the optional `clinicalData` payload sent to Shukhee at booking
/// time (see `shukhee_sdk`'s `ShukheeClient.startConsultation`'s
/// `clinicalData` param) from whatever of the app's own patient/visit data
/// is honestly available today.
///
/// Deliberately scoped to what's real, not everything Shukhee's shape
/// allows for:
/// - `chiefComplaints`: the triage symptom codes already confirmed for this
///   visit, mapped to their human-readable labels via [SymptomCatalog].
/// - `vitals`: temperature and blood pressure only, when present on the
///   most recent ANC/NCD assessment. Deliberately NOT `pulseRate`/
///   `respiratoryRate` -- `VitalsRepository.latestFromLocal` has a
///   confirmed pre-existing bug conflating pulse with respiratory rate, and
///   sending a mislabeled vital sign to a doctor is worse than sending
///   nothing.
/// - `menstrualHistory`: LMP/EDD/Gravida/Para/ALC, only present at all when
///   the patient has a pregnancy snapshot on file (naturally absent for
///   non-ANC patients, not a gap).
/// - `pastIllness`: the visit's structured referral risk-flags/gaps (e.g.
///   "High BP", "Gaps in ANC - ANC Visit 2" -- see
///   `_Step3AiRecoState.widget.referredReasons` in `visit_flow_screen.dart`),
///   the closest-fit vendor field for this data. Absent when the visit
///   raised no risk flags.
/// - `familyHistory`: omitted entirely -- no structured array source exists
///   anywhere in the app today (only booleans / NCD-only comorbidity lists
///   never read from the visit flow); building this would be new
///   data-capture UI, not mapping, so it's out of scope here.
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../../core/db/local_assessment_dao.dart';
import '../../core/db/pregnancy_snapshot_dao.dart';
import '../visit/symptom_catalog.dart';

class TeleconsultClinicalDataBuilder {
  TeleconsultClinicalDataBuilder({
    required this.assessmentDao,
    required this.pregnancySnapshotDao,
  });

  final LocalAssessmentDao assessmentDao;
  final PregnancySnapshotDao pregnancySnapshotDao;

  static final Map<String, String> _symptomLabelByCode = {
    for (final def in [
      ...SymptomCatalog.imciSymptoms,
      ...SymptomCatalog.ancSymptoms,
      ...SymptomCatalog.ncdSymptoms,
      ...SymptomCatalog.tbSymptoms,
    ])
      def.code: def.label,
  };

  /// Returns `null` when nothing at all is available to send (the caller
  /// should then omit `clinicalData` from the booking request entirely,
  /// matching `shukhee_sdk`'s own "omit rather than send empty" contract).
  Future<Map<String, dynamic>?> build({
    required String patientId,
    required Set<String> confirmedSymptoms,
    List<String> referredReasons = const [],
  }) async {
    final result = <String, dynamic>{};

    final chiefComplaints = confirmedSymptoms
        .map((code) => _symptomLabelByCode[code])
        .whereType<String>()
        .toList();
    if (chiefComplaints.isNotEmpty) result['chiefComplaints'] = chiefComplaints;

    // No dedicated "risk flags" field exists in Shukhee's clinicalData shape
    // -- `pastIllness` (a plain string array) is the closest fit for this
    // visit's structured referral risk-flags/gaps (e.g. "High BP", "Gaps in
    // ANC - ANC Visit 2"), distinct from confirmedSymptoms' raw symptom
    // names.
    if (referredReasons.isNotEmpty) result['pastIllness'] = referredReasons;

    final vitals = await _vitalsFor(patientId);
    if (vitals != null) result['vitals'] = [vitals];

    final menstrualHistory = await _menstrualHistoryFor(patientId);
    if (menstrualHistory != null) result['menstrualHistory'] = [menstrualHistory];

    return result.isEmpty ? null : result;
  }

  /// Mirrors `_Step3AiRecoState._parseAncVitals`/`_parseNcdVitals`
  /// (`visit_flow_screen.dart`) for exactly the two fields we send --
  /// intentionally not a shared extraction of those private methods, to
  /// avoid touching that already-working code for a narrower need.
  Future<Map<String, dynamic>?> _vitalsFor(String patientId) async {
    try {
      final assessments = await assessmentDao.getByPatientId(patientId);
      if (assessments.isEmpty) return null;
      final target = assessments.last;
      final data = jsonDecode(target.assessmentDetails) as Map<String, dynamic>;

      double? temperature;
      int? systolic;
      int? diastolic;
      if (target.assessmentType == 'NCD') {
        final bp = data['bpLog'] as Map<String, dynamic>? ?? {};
        temperature = (bp['temperature'] as num?)?.toDouble();
        systolic = (bp['avgSystolic'] as num?)?.toInt();
        diastolic = (bp['avgDiastolic'] as num?)?.toInt();
      } else if (target.assessmentType == 'ANC') {
        final phys = data['medicalHistoryPhysicalExamination'] as Map<String, dynamic>? ?? {};
        systolic = phys['bloodPressureSystolic'] as int?;
        diastolic = phys['bloodPressureDiastolic'] as int?;
      }

      final vitals = <String, dynamic>{};
      if (temperature != null) vitals['temperature'] = temperature.toStringAsFixed(1);
      if (systolic != null && diastolic != null) vitals['bloodPressure'] = '$systolic/$diastolic';
      return vitals.isEmpty ? null : vitals;
    } catch (e) {
      debugPrint('[TeleconsultClinicalDataBuilder] vitals lookup failed: $e');
      return null;
    }
  }

  Future<Map<String, dynamic>?> _menstrualHistoryFor(String patientId) async {
    try {
      final rows = await pregnancySnapshotDao.getAllRows();
      final snapshot = rows[patientId];
      if (snapshot == null) return null;

      final result = <String, dynamic>{};
      if (snapshot.lmpDate != null) {
        result['LMP'] = DateTime.fromMillisecondsSinceEpoch(snapshot.lmpDate!)
            .toIso8601String()
            .split('T')
            .first;
      }
      if (snapshot.eddDate != null) {
        result['EDD'] = DateTime.fromMillisecondsSinceEpoch(snapshot.eddDate!)
            .toIso8601String()
            .split('T')
            .first;
      }
      if (snapshot.gravida != null) result['Gravida'] = snapshot.gravida;
      if (snapshot.parity != null) result['Para'] = snapshot.parity.toString();
      if (snapshot.ageOfLastChild != null && snapshot.ageOfLastChild!.isNotEmpty) {
        result['ALC'] = snapshot.ageOfLastChild;
      }
      return result.isEmpty ? null : result;
    } catch (e) {
      debugPrint('[TeleconsultClinicalDataBuilder] menstrual history lookup failed: $e');
      return null;
    }
  }
}
